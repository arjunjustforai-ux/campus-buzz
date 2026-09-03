import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { fail } from "../domain/errors";
import { track } from "../lib/analytics";
import { writeAudit } from "../lib/audit";
import { callableHandler, num, requireAuth, requireMembership, str } from "../lib/auth";
import { loadCampus, requireFlag } from "../lib/campus";
import { db, inc, serverTs } from "../lib/firestore";
import { ledgerEntryExists, writeCredit } from "../lib/ledger";
import { callableOpts } from "../lib/options";

/** Only verified attendees can review; +10 coins exactly once per (event,user). */
export const submitEventFeedback = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const rating = num(req.data?.rating, "rating", { min: 1, max: 5, int: true });
    const review = str(req.data?.review, "review", { optional: true, max: 1000 });
    const anonymous = req.data?.anonymous === true || actor.user?.privacy?.anonymousFeedback === true;
    const structured = typeof req.data?.structured === "object" && req.data?.structured ? req.data.structured : {};
    const campusId = actor.user?.activeCampusId as string;
    await requireMembership(actor, campusId);
    await requireFlag(campusId, "reviews_enabled");
    const campus = await loadCampus(campusId);

    const evRef = db.collection(COL.events).doc(eventId);
    const fbRef = db.collection(COL.eventFeedback).doc(ids.feedback(eventId, actor.uid));
    const key = ids.ledger.feedback(eventId, actor.uid);
    const result = await db.runTransaction(async (tx) => {
      const [ev, checkin, existing, ledgerExists] = await Promise.all([
        tx.get(evRef),
        tx.get(db.collection(COL.checkins).doc(ids.checkin(eventId, actor.uid))),
        tx.get(fbRef),
        ledgerEntryExists(tx, key),
      ]);
      if (!ev.exists) fail("not_found", "Event not found.");
      if (!checkin.exists) fail("feedback_requires_checkin", "Only checked-in attendees can review this event.");
      if (existing.exists) fail("already_submitted", "You've already reviewed this event.");
      tx.set(fbRef, {
        eventId,
        uid: actor.uid,
        campusId: ev.get("campusId"),
        clubId: ev.get("clubId"),
        rating,
        review: review || null,
        structured,
        anonymous,
        displayName: anonymous ? null : actor.user?.displayName ?? null,
        status: "published",
        at: serverTs(),
      });
      const count = Number(ev.get("stats.feedbackCount") ?? 0) + 1;
      const sum = Number(ev.get("stats.ratingSum") ?? 0) + rating;
      tx.update(evRef, { "stats.feedbackCount": inc(1), "stats.ratingSum": inc(rating), "stats.ratingAvg": Math.round((sum / count) * 100) / 100, [`stats.ratingDist.${rating}`]: inc(1) });
      const coins = campus.featureFlags.buzzcoins_enabled
        ? writeCredit(tx, { key, uid: actor.uid, campusId, type: "credit", reason: "feedback", amount: campus.economy.feedbackReward, refId: eventId, economy: campus.economy, alreadyExists: ledgerExists })
        : 0;
      return { coins };
    });
    await track("feedback_submitted", { uid: actor.uid, campusId, eventId, rating });
    if (result.coins > 0) await track("coins_earned", { uid: actor.uid, campusId, eventId, reason: "feedback", amount: result.coins });
    return { coinsAwarded: result.coins };
  }),
);

/** Campus admin removes an inappropriate review (audited via reports flow). */
export const moderateReview = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const feedbackId = str(req.data?.feedbackId, "feedbackId");
    const reason = str(req.data?.reason, "reason", { max: 500 });
    const ref = db.collection(COL.eventFeedback).doc(feedbackId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found", "Review not found.");
    await requireMembership(actor, snap.get("campusId"), ["campus_admin"]);
    await ref.update({ status: "removed", moderation: { reason, byUid: actor.uid, at: serverTs() } });
    writeAudit({ actorUid: actor.uid, action: "review.remove", entityType: "event_feedback", entityId: feedbackId, campusId: snap.get("campusId"), reason, before: { status: "published" }, after: { status: "removed" } });
    return { ok: true };
  }),
);
