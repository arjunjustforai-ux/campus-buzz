import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { fail } from "../domain/errors";
import { track } from "../lib/analytics";
import { callableHandler, requireAuth, requireMembership, str } from "../lib/auth";
import { loadCampus, requireFlag } from "../lib/campus";
import { db, inc, serverTs, tsToMs } from "../lib/firestore";
import { ledgerEntryExists, writeCredit } from "../lib/ledger";
import { cancelNotificationsByPrefix, enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

/**
 * One-tap RSVP. Server-authoritative transaction: one RSVP per (event,user),
 * capacity enforced, optional waitlist, +5 coins exactly once per pair.
 */
export const createRsvp = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const source = str(req.data?.source, "source", { optional: true, max: 40 }) || "unknown";
    const evRef = db.collection(COL.events).doc(eventId);
    const evPre = await evRef.get();
    if (!evPre.exists) fail("not_found", "Event not found.");
    const campusIds: string[] = evPre.get("participatingCampusIds") ?? [evPre.get("campusId")];
    const userCampusId = actor.user?.activeCampusId as string | undefined;
    if (!userCampusId || !campusIds.includes(userCampusId)) fail("permission_denied", "This event isn't open to your campus.");
    await requireMembership(actor, userCampusId);
    await requireFlag(userCampusId, "discovery_enabled");
    const campus = await loadCampus(evPre.get("campusId"));
    const tribeIds: string[] = actor.user?.tribeIds ?? [];

    const rsvpRef = db.collection(COL.rsvps).doc(ids.rsvp(eventId, actor.uid));
    const ledgerKey = ids.ledger.rsvp(eventId, actor.uid);
    const result = await db.runTransaction(async (tx) => {
      const [ev, rsvp, ledgerExists] = await Promise.all([tx.get(evRef), tx.get(rsvpRef), ledgerEntryExists(tx, ledgerKey)]);
      const e = ev.data()!;
      if (e.status !== "published") fail(e.status === "cancelled" ? "event_cancelled" : "event_not_open", "This event isn't open for RSVPs.");
      const nowMs = Date.now();
      const closesAt = tsToMs(e.registrationClosesAt) ?? tsToMs(e.endAt) ?? nowMs;
      if (nowMs > closesAt) fail("rsvp_closed", "RSVPs for this event have closed.");
      if (rsvp.exists && rsvp.get("status") !== "cancelled") fail("already_rsvped", "You're already on the list.");
      const capacity = Number(e.capacity ?? 0);
      const confirmed = Number(e.stats?.rsvpCount ?? 0);
      let status: "confirmed" | "waitlisted" = "confirmed";
      if (capacity > 0 && confirmed >= capacity) {
        if (!e.waitlistEnabled) fail("event_full", "This event is full.");
        status = "waitlisted";
      }
      tx.set(rsvpRef, {
        eventId,
        uid: actor.uid,
        campusId: e.campusId,
        userCampusId,
        status,
        tribeIds,
        source,
        createdAt: rsvp.exists ? rsvp.get("createdAt") : serverTs(),
        updatedAt: serverTs(),
        cancelledAt: null,
        startAt: e.startAt,
        eventTitle: e.title,
      });
      const tribeInc: Record<string, unknown> = {};
      for (const t of tribeIds) tribeInc[`tribeRsvps.${t}`] = inc(1);
      tx.update(evRef, {
        [status === "confirmed" ? "stats.rsvpCount" : "stats.waitlistCount"]: inc(1),
        ...(status === "confirmed" ? tribeInc : {}),
      });
      tx.set(db.collection(COL.participationStats).doc(actor.uid), { totalRsvps: inc(1), updatedAt: serverTs() }, { merge: true });
      const coins = writeCredit(tx, { key: ledgerKey, uid: actor.uid, campusId: userCampusId, type: "credit", reason: "rsvp", amount: campus.economy.rsvpReward, refId: eventId, economy: campus.economy, alreadyExists: ledgerExists });
      return { status, coins, title: e.title as string, startMs: tsToMs(e.startAt) ?? nowMs };
    });

    await track("rsvp_created", { uid: actor.uid, campusId: userCampusId, eventId, source, status: result.status, tribeIds });
    if (result.coins > 0) await track("coins_earned", { uid: actor.uid, campusId: userCampusId, eventId, reason: "rsvp", amount: result.coins });
    await enqueueNotification({ uid: actor.uid, campusId: userCampusId, category: "transactional", title: result.status === "confirmed" ? "You're in." : "You're on the waitlist.", body: `${result.title}${result.coins > 0 ? ` · +${result.coins} BuzzCoins` : ""}`, route: `/events/${eventId}`, dedupeKey: `rsvp:${eventId}:${actor.uid}:${Date.now()}` });
    await scheduleReminders(eventId, actor.uid, userCampusId, result.title, result.startMs);
    return { status: result.status, coinsAwarded: result.coins };
  }),
);

export const cancelRsvp = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const evRef = db.collection(COL.events).doc(eventId);
    const rsvpRef = db.collection(COL.rsvps).doc(ids.rsvp(eventId, actor.uid));
    const promoted = await db.runTransaction(async (tx) => {
      const [ev, rsvp] = await Promise.all([tx.get(evRef), tx.get(rsvpRef)]);
      if (!ev.exists) fail("not_found", "Event not found.");
      if (!rsvp.exists || rsvp.get("status") === "cancelled") return null;
      const wasConfirmed = rsvp.get("status") === "confirmed";
      const tribeIds: string[] = rsvp.get("tribeIds") ?? [];
      // All reads must precede writes inside a transaction: fetch the promotion candidate first.
      const wl = wasConfirmed && ev.get("waitlistEnabled")
        ? await tx.get(db.collection(COL.rsvps).where("eventId", "==", eventId).where("status", "==", "waitlisted").orderBy("createdAt").limit(1))
        : null;
      tx.update(rsvpRef, { status: "cancelled", cancelledAt: serverTs(), updatedAt: serverTs() });
      const tribeDec: Record<string, unknown> = {};
      for (const t of tribeIds) tribeDec[`tribeRsvps.${t}`] = inc(-1);
      tx.update(evRef, { [wasConfirmed ? "stats.rsvpCount" : "stats.waitlistCount"]: inc(-1), ...(wasConfirmed ? tribeDec : {}) });
      tx.set(db.collection(COL.participationStats).doc(actor.uid), { totalRsvps: inc(-1), updatedAt: serverTs() }, { merge: true });
      // Promote the oldest waitlisted RSVP, if any.
      if (wl) {
        if (!wl.empty) {
          const p = wl.docs[0];
          const pt: string[] = p.get("tribeIds") ?? [];
          const pInc: Record<string, unknown> = {};
          for (const t of pt) pInc[`tribeRsvps.${t}`] = inc(1);
          tx.update(p.ref, { status: "confirmed", promotedAt: serverTs(), updatedAt: serverTs() });
          tx.update(evRef, { "stats.rsvpCount": inc(1), "stats.waitlistCount": inc(-1), ...pInc });
          return { uid: p.get("uid") as string, campusId: p.get("userCampusId") as string, title: ev.get("title") as string, startMs: tsToMs(ev.get("startAt")) ?? Date.now() };
        }
      }
      return null;
    });
    await cancelNotificationsByPrefix(`reminder:${eventId}:${actor.uid}`);
    await track("rsvp_cancelled", { uid: actor.uid, campusId: actor.user?.activeCampusId, eventId });
    if (promoted) {
      await enqueueNotification({ uid: promoted.uid, campusId: promoted.campusId, category: "transactional", title: "A spot opened up — you're in.", body: promoted.title, route: `/events/${eventId}`, dedupeKey: `rsvp:promoted:${eventId}:${promoted.uid}` });
      await scheduleReminders(eventId, promoted.uid, promoted.campusId, promoted.title, promoted.startMs);
    }
    return { ok: true };
  }),
);

/** 24h and 1h reminders. Deduped by key; skipped if already in the past. */
export async function scheduleReminders(eventId: string, uid: string, campusId: string, title: string, startMs: number): Promise<void> {
  const plan: Array<{ tag: string; at: number; body: string }> = [
    { tag: "24h", at: startMs - 24 * 3600000, body: `${title} is tomorrow. Your Tribe is showing up.` },
    { tag: "1h", at: startMs - 3600000, body: `${title} starts in an hour. Scan the QR when you arrive for +BuzzCoins.` },
  ];
  for (const p of plan) {
    if (p.at <= Date.now()) continue;
    await enqueueNotification({ uid, campusId, category: "reminder", title: "Don't miss what's happening.", body: p.body, route: `/events/${eventId}`, scheduledFor: new Date(p.at), dedupeKey: `reminder:${eventId}:${uid}:${p.tag}` });
  }
}
