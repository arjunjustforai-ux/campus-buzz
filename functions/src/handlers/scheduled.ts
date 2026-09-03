import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { COL } from "../config/collections";
import { localDateKey } from "../domain/time";
import { track } from "../lib/analytics";
import { callableHandler, requireAuth, requireMembership, str } from "../lib/auth";
import { loadCampus, normalizeCampus } from "../lib/campus";
import { db, FieldValue, forEachPage, serverTs, Timestamp, tsToMs } from "../lib/firestore";
import { ledgerEntryExists, writeExpiry } from "../lib/ledger";
import { decideDelivery, enqueueNotification, sendPush } from "../lib/notifications";
import { callableOpts, scheduleOpts } from "../lib/options";
import { closeEventInternal } from "./events";

/* ------------------------------------------------------------------ */
/* Coin expiry — ledger-based, FIFO, idempotent                        */
/* ------------------------------------------------------------------ */

export async function expireCoinsOnce(nowMs = Date.now()): Promise<{ expiredEntries: number; coins: number }> {
  let expiredEntries = 0, coins = 0;
  const q = db.collection(COL.coinLedger).where("type", "==", "credit").where("expired", "==", false).where("expiresAt", "<=", Timestamp.fromMillis(nowMs)).orderBy("expiresAt").limit(400);
  const snap = await q.get();
  for (const d of snap.docs) {
    const amt = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(d.ref);
      if (!fresh.exists || fresh.get("expired")) return 0;
      const exists = await ledgerEntryExists(tx, `expiry:${d.id}`);
      // Only the un-spent portion expires (FIFO: debits consumed oldest credits first).
      const remaining = Number(fresh.get("remaining") ?? 0);
      if (remaining <= 0) { tx.update(d.ref, { expired: true, expiredAt: serverTs() }); return 0; }
      return writeExpiry(tx, { creditKey: d.id, uid: fresh.get("uid"), campusId: fresh.get("campusId"), remaining, alreadyExists: exists });
    });
    if (amt > 0) { expiredEntries++; coins += amt; await track("coins_expired", { uid: d.get("uid"), campusId: d.get("campusId"), amount: amt }); }
  }
  return { expiredEntries, coins };
}

/**
 * Debits consume credits FIFO: after every redemption we reduce `remaining` on the
 * oldest un-expired credits so expiry only removes what was never spent. Runs as a
 * trigger-free sweep each hour for robustness (idempotent — consumption is stored
 * on the debit entry).
 */
export async function applyFifoConsumption(): Promise<number> {
  let processed = 0;
  const debits = await db.collection(COL.coinLedger).where("type", "in", ["debit", "adjustment"]).where("fifoApplied", "==", false).limit(200).get();
  for (const d of debits.docs) {
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(d.ref);
      if (fresh.get("fifoApplied")) return;
      let left = Math.abs(Number(fresh.get("amount")));
      const credits = await tx.get(db.collection(COL.coinLedger).where("uid", "==", fresh.get("uid")).where("type", "==", "credit").where("remaining", ">", 0).orderBy("remaining").orderBy("createdAt").limit(100));
      const sorted = credits.docs.sort((a, b) => (tsToMs(a.get("createdAt")) ?? 0) - (tsToMs(b.get("createdAt")) ?? 0));
      const consumed: Array<{ key: string; amount: number }> = [];
      for (const c of sorted) {
        if (left <= 0) break;
        const take = Math.min(Number(c.get("remaining")), left);
        left -= take;
        consumed.push({ key: c.id, amount: take });
        tx.update(c.ref, { remaining: FieldValue.increment(-take) });
      }
      tx.update(d.ref, { fifoApplied: true, consumed });
    });
    processed++;
  }
  return processed;
}

export const expireBuzzCoins = onSchedule({ ...scheduleOpts, schedule: "30 3 * * *", timeZone: "Asia/Kolkata" }, async () => {
  await applyFifoConsumption();
  const r = await expireCoinsOnce();
  console.log("expireBuzzCoins", r);
  await refreshExpiringSoon();
});

export const applyLedgerFifo = onSchedule({ ...scheduleOpts, schedule: "every 60 minutes" }, async () => {
  const n = await applyFifoConsumption();
  if (n) console.log("fifo applied", n);
});

/** Materialize "expiring within 14 days" on balances so the app can warn users cheaply. */
export async function refreshExpiringSoon(): Promise<void> {
  const limit = Timestamp.fromMillis(Date.now() + 14 * 86400000);
  const soon = await db.collection(COL.coinLedger).where("type", "==", "credit").where("expired", "==", false).where("expiresAt", "<=", limit).select("uid", "remaining", "expiresAt").get();
  const byUid = new Map<string, { amount: number; earliest: number }>();
  soon.docs.forEach((d) => { const r = Number(d.get("remaining") ?? 0); if (r <= 0) return; const cur = byUid.get(d.get("uid")) ?? { amount: 0, earliest: Number.MAX_SAFE_INTEGER }; cur.amount += r; cur.earliest = Math.min(cur.earliest, tsToMs(d.get("expiresAt")) ?? cur.earliest); byUid.set(d.get("uid"), cur); });
  const b = db.batch(); let n = 0;
  for (const [uid, v] of byUid) { b.set(db.collection(COL.coinBalances).doc(uid), { expiringSoon: v.amount, expiringSoonAt: Timestamp.fromMillis(v.earliest) }, { merge: true }); if (++n >= 450) break; }
  await b.commit();
}

/* ------------------------------------------------------------------ */
/* Notification delivery                                               */
/* ------------------------------------------------------------------ */

export async function processNotificationJobsOnce(limit = 300): Promise<{ sent: number; skipped: number; failed: number }> {
  const due = await db.collection(COL.notificationJobs).where("status", "==", "pending").where("scheduledFor", "<=", Timestamp.now()).orderBy("scheduledFor").limit(limit).get();
  let sent = 0, skipped = 0, failed = 0;
  const campusCache = new Map<string, { tz: string; cap: number }>();
  for (const job of due.docs) {
    // Claim atomically so two schedulers never double-send.
    const claimed = await db.runTransaction(async (tx) => { const f = await tx.get(job.ref); if (f.get("status") !== "pending") return false; tx.update(job.ref, { status: "processing", attempts: FieldValue.increment(1) }); return true; });
    if (!claimed) continue;
    const j = job.data();
    try {
      if (!campusCache.has(j.campusId)) { const c = await loadCampus(j.campusId); campusCache.set(j.campusId, { tz: c.timezone, cap: c.economy.engagementNotificationCapPerDay }); }
      const { tz, cap } = campusCache.get(j.campusId)!;
      const decision = await decideDelivery(j.uid, j.category, tz, cap);
      const dayKey = localDateKey(new Date(), tz);
      if (!decision.send) {
        await job.ref.update({ status: "skipped", skipReason: decision.reason, processedAt: serverTs() });
        await db.collection(COL.notificationDeliveryLogs).add({ jobId: job.id, uid: j.uid, campusId: j.campusId, category: j.category, status: "skipped", reason: decision.reason, dayKey, at: serverTs() });
        skipped++;
        continue;
      }
      const r = await sendPush(decision.tokens, { title: j.title, body: j.body, route: j.route, data: j.data });
      if (r.invalidTokens.length > 0) await db.collection(COL.users).doc(j.uid).update({ fcmTokens: FieldValue.arrayRemove(...r.invalidTokens) });
      await job.ref.update({ status: r.success > 0 ? "sent" : "failed", sentAt: serverTs(), result: { success: r.success, failure: r.failure } });
      await db.collection(COL.notificationDeliveryLogs).add({ jobId: job.id, uid: j.uid, campusId: j.campusId, category: j.category, status: r.success > 0 ? "sent" : "failed", dayKey, title: j.title, route: j.route ?? null, at: serverTs() });
      await track("notification_sent", { uid: j.uid, campusId: j.campusId, category: j.category, success: r.success });
      if (r.success > 0) sent++; else failed++;
    } catch (e) {
      console.error("notification job failed", job.id, e);
      await job.ref.update({ status: (j.attempts ?? 0) >= 3 ? "failed" : "pending", lastError: String(e) });
      failed++;
    }
  }
  return { sent, skipped, failed };
}

export const processNotificationJobs = onSchedule({ ...scheduleOpts, schedule: "every 5 minutes" }, async () => {
  const r = await processNotificationJobsOnce();
  if (r.sent || r.failed) console.log("notifications", r);
});

/* ------------------------------------------------------------------ */
/* Event lifecycle sweeps                                              */
/* ------------------------------------------------------------------ */

/** Closes events whose check-in window has passed (feedback prompts + organizer bonus), archives old ones. */
export async function closeEndedEventsOnce(nowMs = Date.now()): Promise<{ closed: number; archived: number }> {
  let closed = 0, archived = 0;
  const ended = await db.collection(COL.events).where("status", "==", "published").where("checkinClosesAt", "<=", Timestamp.fromMillis(nowMs)).limit(200).get();
  for (const d of ended.docs) { const r = await closeEventInternal(d.id, null); if (r.closed) closed++; }
  const old = await db.collection(COL.events).where("status", "in", ["completed", "cancelled"]).where("endAt", "<=", Timestamp.fromMillis(nowMs - 90 * 86400000)).limit(200).get();
  for (const d of old.docs) { await d.ref.update({ status: "archived", archivedAt: serverTs() }); archived++; }
  return { closed, archived };
}

export const closeEndedEvents = onSchedule({ ...scheduleOpts, schedule: "every 15 minutes" }, async () => {
  const r = await closeEndedEventsOnce();
  if (r.closed || r.archived) console.log("closeEndedEvents", r);
});

/** Engagement: Tribe-relevant recommendation + streak-at-risk reminder (respects caps). Daily 18:00 campus time. */
export const sendEngagementNudges = onSchedule({ ...scheduleOpts, schedule: "0 18 * * *", timeZone: "Asia/Kolkata" }, async () => {
  const campuses = await db.collection(COL.campuses).where("status", "==", "active").get();
  for (const c of campuses.docs) {
    const campus = normalizeCampus(c.id, c.data());
    const upcoming = await db.collection(COL.events).where("participatingCampusIds", "array-contains", campus.id).where("status", "==", "published").where("startAt", ">=", Timestamp.now()).where("startAt", "<=", Timestamp.fromMillis(Date.now() + 3 * 86400000)).orderBy("startAt").limit(20).get();
    if (upcoming.empty) continue;
    const dayKey = localDateKey(new Date(), campus.timezone);
    await forEachPage(db.collection(COL.memberships).where("campusId", "==", campus.id).where("status", "==", "active"), 300, async (docs) => {
      for (const m of docs) {
        const tribes: string[] = m.get("tribeIds") ?? [];
        const match = upcoming.docs.find((e) => (e.get("tribeIds") as string[]).some((t) => tribes.includes(t)));
        if (!match) continue;
        await enqueueNotification({ uid: m.get("uid"), campusId: campus.id, category: "engagement", title: "Your tribe is showing up.", body: `${match.get("title")} · ${match.get("clubName")}`, route: `/events/${match.id}`, dedupeKey: `nudge:${campus.id}:${dayKey}:${m.get("uid")}` });
      }
    });
  }
});

/** Admin/dev trigger to run all sweeps now (used by the demo and integration tests). */
export const runMaintenanceNow = onCall(
  { ...callableOpts, timeoutSeconds: 300 },
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const events = await closeEndedEventsOnce();
    const fifo = await applyFifoConsumption();
    const expiry = await expireCoinsOnce();
    await refreshExpiringSoon();
    const notifications = await processNotificationJobsOnce();
    return { events, fifo, expiry, notifications };
  }),
);
