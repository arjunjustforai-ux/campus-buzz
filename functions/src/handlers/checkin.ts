import { randomBytes } from "node:crypto";
import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { QR_TOKEN } from "../config/defaults";
import { qrSigningSecret } from "../config/secrets";
import { checkinReward } from "../domain/economy";
import { fail } from "../domain/errors";
import { signToken, verifyToken, windowIndex } from "../domain/qrToken";
import { multiplierAppliesForCheckin, updateStreak } from "../domain/streaks";
import { hourBucket, localParts } from "../domain/time";
import type { StreakState } from "../domain/types";
import { track } from "../lib/analytics";
import { writeAudit } from "../lib/audit";
import { callableHandler, canManageEvent, requireAuth, requireMembership, str } from "../lib/auth";
import { loadCampus, requireFlag } from "../lib/campus";
import { db, inc, serverTs, Timestamp, tsToMs } from "../lib/firestore";
import { ledgerEntryExists, writeCredit } from "../lib/ledger";
import { enqueueNotification } from "../lib/notifications";
import { callableOpts, callableOptsWithQrSecret } from "../lib/options";
import { evaluateQuestsForCheckin } from "./quests";

async function loadManagedEvent(actorUid: string, eventId: string, req: Parameters<typeof requireAuth>[0]) {
  const actor = await requireAuth(req);
  const snap = await db.collection(COL.events).doc(eventId).get();
  if (!snap.exists) fail("not_found", "Event not found.");
  const ev = snap.data()!;
  const m = await requireMembership(actor, ev.campusId, ["organizer", "campus_admin"]);
  if (!canManageEvent(m, actorUid, ev)) fail("permission_denied", "You don't have access to this event.");
  return { actor, ev, ref: snap.ref };
}

/** Organizer activates check-in (≈30 min before start). Creates a fresh session nonce. */
export const startEventCheckin = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const eventId = str(req.data?.eventId, "eventId");
    const { actor, ev, ref } = await loadManagedEvent(req.auth?.uid ?? "", eventId, req);
    if (ev.status !== "published") fail("event_not_open", "Only published events can open check-in.");
    await requireFlag(ev.campusId, "qr_checkin_enabled");
    const nowMs = Date.now();
    const opensAt = tsToMs(ev.checkinOpensAt) ?? 0;
    const closesAt = tsToMs(ev.checkinClosesAt) ?? Number.MAX_SAFE_INTEGER;
    if (nowMs < opensAt) fail("checkin_not_active", "Check-in opens 30 minutes before the event starts.", { opensAt });
    if (nowMs > closesAt) fail("checkin_window_closed", "The check-in window for this event has closed.");
    const nonce = randomBytes(8).toString("base64url");
    await db.collection(COL.eventQrSessions).doc(eventId).set({ eventId, campusId: ev.campusId, active: true, nonce, startedAt: serverTs(), startedBy: actor.uid, scanFailures: 0, scanSuccesses: 0 });
    await ref.update({ checkinActive: true, updatedAt: serverTs() });
    await track("organizer_qr_started", { uid: actor.uid, campusId: ev.campusId, eventId, organizerId: ev.clubId });
    return { ok: true, nonce, rotationSeconds: QR_TOKEN.rotationSeconds };
  }),
);

export const stopEventCheckin = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const eventId = str(req.data?.eventId, "eventId");
    const { ev, ref } = await loadManagedEvent(req.auth?.uid ?? "", eventId, req);
    await db.collection(COL.eventQrSessions).doc(eventId).set({ active: false, stoppedAt: serverTs() }, { merge: true });
    await ref.update({ checkinActive: false, updatedAt: serverTs() });
    return { ok: true, campusId: ev.campusId };
  }),
);

/**
 * Issue the current rotating token. Called by the organizer's live screen every
 * rotation. Tokens are HMAC-signed server-side; the app never holds the secret.
 */
export const issueEventQrToken = onCall(
  callableOptsWithQrSecret,
  callableHandler(async (req) => {
    const eventId = str(req.data?.eventId, "eventId");
    const { ev } = await loadManagedEvent(req.auth?.uid ?? "", eventId, req);
    const session = await db.collection(COL.eventQrSessions).doc(eventId).get();
    if (!session.exists || !session.get("active") || !ev.checkinActive) fail("checkin_not_active", "Start check-in first.");
    const nowMs = Date.now();
    if (nowMs > (tsToMs(ev.checkinClosesAt) ?? nowMs)) fail("checkin_window_closed", "The check-in window has closed.");
    const w = windowIndex(nowMs);
    const token = signToken({ e: eventId, c: ev.campusId, w, n: session.get("nonce"), v: QR_TOKEN.version }, qrSigningSecret());
    const expiresAtMs = (w + 1) * QR_TOKEN.rotationSeconds * 1000;
    return { token, expiresAtMs, rotationSeconds: QR_TOKEN.rotationSeconds, checkinCount: ev.stats?.checkinCount ?? 0, rsvpCount: ev.stats?.rsvpCount ?? 0 };
  }),
);

interface CheckinOutcome {
  coins: number;
  streak: number;
  multiplierApplied: boolean;
  referralAwarded: number;
  alreadyCheckedIn: boolean;
  eventTitle: string;
  certificateRef: string | null;
}

/**
 * Core check-in transaction shared by QR and manual paths. Idempotent per
 * (event,user); coins awarded exactly once; streak/referral/quests updated.
 */
export async function recordCheckin(params: {
  eventId: string;
  uid: string;
  method: "qr" | "manual";
  byUid?: string;
  reason?: string;
  requireRsvp?: boolean;
}): Promise<CheckinOutcome> {
  const { eventId, uid, method } = params;
  const evRef = db.collection(COL.events).doc(eventId);
  const checkinRef = db.collection(COL.checkins).doc(ids.checkin(eventId, uid));
  const statsRef = db.collection(COL.participationStats).doc(uid);
  const userRef = db.collection(COL.users).doc(uid);
  const refRef = db.collection(COL.referrals).doc(uid);
  const ledgerKey = ids.ledger.checkin(eventId, uid);

  const out = await db.runTransaction(async (tx) => {
    // Every read happens here, before any write (Firestore transaction rule).
    const [ev, existing, stats, user, referral, ledgerExists, referralLedgerExists] = await Promise.all([
      tx.get(evRef),
      tx.get(checkinRef),
      tx.get(statsRef),
      tx.get(userRef),
      tx.get(refRef),
      ledgerEntryExists(tx, ledgerKey),
      ledgerEntryExists(tx, ids.ledger.referral(uid)),
    ]);
    if (!ev.exists) fail("not_found", "Event not found.");
    const e = ev.data()!;
    if (existing.exists) {
      return { coins: 0, streak: stats.get("streak") ?? 0, multiplierApplied: false, referralAwarded: 0, alreadyCheckedIn: true, eventTitle: e.title, certificateRef: existing.get("certificateRef") ?? null, campusId: e.campusId as string, userCampusId: user.get("activeCampusId") as string, tribeIds: [] as string[] };
    }
    if (e.status === "cancelled") fail("event_cancelled", "This event was cancelled.");
    if (!user.exists || user.get("status") !== "active") fail("account_suspended");
    const userCampusId: string = user.get("activeCampusId");
    const participating: string[] = e.participatingCampusIds ?? [e.campusId];
    if (!participating.includes(userCampusId)) fail("permission_denied", "This event isn't open to your campus.");
    const campus = await loadCampus(e.campusId, tx);
    const nowMs = Date.now();
    if (method === "qr") {
      if (!e.checkinActive) fail("checkin_not_active", "Check-in isn't open yet. Ask the organizer to start it.");
      if (nowMs > (tsToMs(e.checkinClosesAt) ?? nowMs)) fail("checkin_window_closed", "The check-in window has closed.");
    } else {
      // Manual: allowed during the window and the correction window after close.
      const limit = (tsToMs(e.checkinClosesAt) ?? nowMs) + campus.economy.manualCorrectionWindowHours * 3600000;
      if (nowMs > limit) fail("checkin_window_closed", "The manual correction window has closed.");
    }
    if (params.requireRsvp) {
      const rsvp = await tx.get(db.collection(COL.rsvps).doc(ids.rsvp(eventId, uid)));
      if (!rsvp.exists || rsvp.get("status") === "cancelled") fail("rsvp_required", "RSVP before checking in.");
    }

    const tribeIds: string[] = user.get("tribeIds") ?? [];
    const prev: StreakState = { streak: stats.get("streak") ?? 0, lastWeekKey: stats.get("lastWeekKey") ?? null, multiplierActive: stats.get("multiplierActive") ?? false };
    const checkinAt = new Date(nowMs);
    const next = updateStreak(prev, checkinAt, campus.timezone, campus.economy);
    const flags = campus.featureFlags;
    const multiplierApplied = flags.streaks_enabled && multiplierAppliesForCheckin(next, campus.economy);
    const amount = flags.buzzcoins_enabled ? checkinReward(campus.economy, multiplierApplied) : 0;
    const coins = writeCredit(tx, { key: ledgerKey, uid, campusId: userCampusId, type: "credit", reason: "checkin", amount, refId: eventId, economy: campus.economy, alreadyExists: ledgerExists, meta: { method, multiplierApplied, streak: next.streak } });

    const certificateRef = e.certificateEnabled ? `CB-${eventId.slice(0, 6).toUpperCase()}-${uid.slice(0, 6).toUpperCase()}` : null;
    tx.set(checkinRef, {
      eventId,
      uid,
      campusId: e.campusId,
      userCampusId,
      method,
      byUid: params.byUid ?? null,
      reason: params.reason ?? null,
      tribeIds,
      coinsAwarded: coins,
      streakAtCheckin: next.streak,
      multiplierApplied,
      certificateRef,
      eventTitle: e.title,
      clubId: e.clubId,
      tags: e.tags ?? [],
      eventTribeIds: e.tribeIds ?? [],
      startAt: e.startAt,
      at: Timestamp.fromDate(checkinAt),
      weekKey: next.lastWeekKey,
    });
    const tribeInc: Record<string, unknown> = {};
    for (const t of tribeIds) tribeInc[`tribeCheckins.${t}`] = inc(1);
    tx.update(evRef, { "stats.checkinCount": inc(1), ...(method === "manual" ? { "stats.manualCheckinCount": inc(1) } : {}), ...tribeInc, updatedAt: serverTs() });

    const lp = localParts(checkinAt, campus.timezone);
    const tagInc: Record<string, unknown> = {};
    for (const t of [...(e.tags ?? []), ...(e.tribeIds ?? [])]) tagInc[`attendedTags.${t}`] = inc(1);
    tx.set(statsRef, { uid, campusId: userCampusId, streak: next.streak, lastWeekKey: next.lastWeekKey, multiplierActive: next.multiplierActive, totalCheckins: inc(1), lastCheckinAt: serverTs(), [`attendedWeekdays.${lp.weekday}`]: inc(1), [`attendedHourBuckets.${hourBucket(lp.hour)}`]: inc(1), ...tagInc, updatedAt: serverTs() }, { merge: true });

    // Referral: referrer earns once when the referred student completes first verified attendance.
    let referralAwarded = 0;
    if (referral.exists && !referral.get("rewardAwarded") && flags.referrals_enabled) {
      const rKey = ids.ledger.referral(uid);
      const rExists = referralLedgerExists;
      referralAwarded = writeCredit(tx, { key: rKey, uid: referral.get("referrerUid"), campusId: referral.get("campusId"), type: "credit", reason: "referral", amount: campus.economy.referralReward, refId: uid, economy: campus.economy, alreadyExists: rExists, meta: { eventId } });
      tx.update(refRef, { rewardAwarded: true, firstAttendanceAt: serverTs(), firstAttendanceEventId: eventId });
    }
    if (method === "manual") {
      writeAudit({ actorUid: params.byUid ?? "system", action: "checkin.manual", entityType: "checkin", entityId: checkinRef.id, campusId: e.campusId, reason: params.reason, after: { eventId, uid, coins } }, tx);
    }
    return { coins, streak: next.streak, multiplierApplied, referralAwarded, alreadyCheckedIn: false, eventTitle: e.title as string, certificateRef, campusId: e.campusId as string, userCampusId, tribeIds, referrerUid: referral.exists ? (referral.get("referrerUid") as string) : null };
  });

  if (!out.alreadyCheckedIn) {
    await track(method === "qr" ? "checkin_success" : "manual_checkin", { uid, campusId: out.userCampusId, eventId, tribeIds: out.tribeIds, coins: out.coins, streak: out.streak });
    if (out.coins > 0) await track("coins_earned", { uid, campusId: out.userCampusId, eventId, reason: "checkin", amount: out.coins, multiplierApplied: out.multiplierApplied });
    if (out.referralAwarded > 0 && out.referrerUid) {
      await track("referral_first_attendance", { uid: out.referrerUid, campusId: out.campusId, referredUid: uid, amount: out.referralAwarded });
      await enqueueNotification({ uid: out.referrerUid, campusId: out.campusId, category: "transactional", title: `+${out.referralAwarded} BuzzCoins`, body: "A friend you referred just showed up to their first event.", route: "/rewards", dedupeKey: `referral:${uid}` });
    }
    await evaluateQuestsForCheckin({ uid, campusId: out.userCampusId, eventId, tribeIds: out.tribeIds }).catch((e) => console.error("quest evaluation failed", e));
  }
  return { coins: out.coins, streak: out.streak, multiplierApplied: out.multiplierApplied, referralAwarded: out.referralAwarded, alreadyCheckedIn: out.alreadyCheckedIn, eventTitle: out.eventTitle, certificateRef: out.certificateRef };
}

/** Student scans the rotating QR → token validated server-side → verified check-in. */
export const checkInWithQr = onCall(
  callableOptsWithQrSecret,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const token = str(req.data?.token, "token", { max: 1000 });
    const campusId = actor.user?.activeCampusId as string | undefined;
    if (!campusId) fail("not_campus_member", "Finish onboarding first.");
    await requireMembership(actor, campusId);
    await requireFlag(campusId, "qr_checkin_enabled");
    const verified = verifyToken(token, qrSigningSecret(), Date.now());
    if (!verified.ok) {
      await track("checkin_failure", { uid: actor.uid, campusId, reason: verified.reason });
      if (verified.reason === "expired") fail("qr_expired", "This check-in code has expired. Ask the organizer to refresh the QR.");
      fail("qr_invalid", "That doesn't look like a CampusBuzz check-in code.");
    }
    const { e: eventId, n: nonce } = verified.ok ? verified.payload : { e: "", n: "" };
    const session = await db.collection(COL.eventQrSessions).doc(eventId).get();
    if (!session.exists || !session.get("active") || session.get("nonce") !== nonce) {
      await session.ref.set({ scanFailures: inc(1) }, { merge: true });
      await track("checkin_failure", { uid: actor.uid, campusId, eventId, reason: "session_inactive" });
      fail("qr_expired", "This check-in code has expired. Ask the organizer to refresh the QR.");
    }
    const out = await recordCheckin({ eventId, uid: actor.uid, method: "qr" });
    if (!out.alreadyCheckedIn) await session.ref.set({ scanSuccesses: inc(1) }, { merge: true });
    return out;
  }),
);

/** Organizer manual fallback. Requires reason; audited; identical economy treatment. */
export const manualCheckIn = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const eventId = str(req.data?.eventId, "eventId");
    const targetUid = str(req.data?.uid, "uid");
    const reason = str(req.data?.reason, "reason", { optional: true, max: 300 }) || "Manual fallback";
    const { actor, ev } = await loadManagedEvent(req.auth?.uid ?? "", eventId, req);
    if (ev.status !== "published" && ev.status !== "completed") fail("event_not_open", "Check-in isn't available for this event.");
    const targetMembership = await db.collection(COL.memberships).where("uid", "==", targetUid).where("campusId", "in", ev.participatingCampusIds ?? [ev.campusId]).limit(1).get();
    if (targetMembership.empty) fail("not_found", "That student isn't a member of a participating campus.");
    return recordCheckin({ eventId, uid: targetUid, method: "manual", byUid: actor.uid, reason });
  }),
);

/** Organizer attendee lookup for manual check-in (name/email prefix within RSVPs + campus). */
export const searchAttendees = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const eventId = str(req.data?.eventId, "eventId");
    const q = str(req.data?.query, "query", { max: 60 }).toLowerCase();
    const { ev } = await loadManagedEvent(req.auth?.uid ?? "", eventId, req);
    const rsvps = await db.collection(COL.rsvps).where("eventId", "==", eventId).where("status", "in", ["confirmed", "waitlisted"]).limit(500).get();
    const rsvpUids = new Set(rsvps.docs.map((d) => d.get("uid") as string));
    const members = await db.collection(COL.memberships).where("campusId", "==", ev.campusId).where("status", "==", "active").limit(2000).get();
    const checkins = await db.collection(COL.checkins).where("eventId", "==", eventId).select("uid").get();
    const checked = new Set(checkins.docs.map((d) => d.get("uid") as string));
    const results = members.docs
      .map((d) => ({ uid: d.get("uid") as string, displayName: (d.get("displayName") as string) ?? "", rsvped: rsvpUids.has(d.get("uid")), checkedIn: checked.has(d.get("uid")) }))
      .filter((r) => r.displayName.toLowerCase().includes(q) || r.uid.toLowerCase().startsWith(q))
      .sort((a, b) => Number(b.rsvped) - Number(a.rsvped) || a.displayName.localeCompare(b.displayName))
      .slice(0, 25);
    return { results };
  }),
);
