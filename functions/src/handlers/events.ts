import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { organizerBonusEligible } from "../domain/economy";
import { fail } from "../domain/errors";
import { searchTokens } from "../domain/search";
import type { EventStatus } from "../domain/types";
import { track } from "../lib/analytics";
import { writeAudit } from "../lib/audit";
import { callableHandler, canManageEvent, num, requireAuth, requireMembership, str, strArray } from "../lib/auth";
import { loadCampus, featureFlags } from "../lib/campus";
import { db, forEachPage, inc, serverTs, Timestamp, toDate, tsToMs } from "../lib/firestore";
import { ledgerEntryExists, writeCredit } from "../lib/ledger";
import { cancelNotificationsByPrefix, enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

interface EventInput {
  title: string;
  description: string;
  clubId: string;
  posterUrl: string;
  startAt: Date;
  endAt: Date;
  location: { name: string; address: string; lat: number | null; lng: number | null };
  capacity: number;
  waitlistEnabled: boolean;
  tribeIds: string[];
  tags: string[];
  participatingCampusIds: string[];
  contact: string;
  registrationClosesAt: Date | null;
  certificateEnabled: boolean;
}

function parseEventInput(data: Record<string, unknown>, campusId: string): EventInput {
  const startAt = toDate(data.startAt);
  const endAt = toDate(data.endAt);
  if (!startAt || !endAt) fail("invalid_argument", "Start and end time are required.");
  if (endAt! <= startAt!) fail("invalid_argument", "End time must be after start time.");
  const loc = (data.location ?? {}) as Record<string, unknown>;
  const lat = loc.lat === undefined || loc.lat === null ? null : num(loc.lat, "location.lat", { min: -90, max: 90 });
  const lng = loc.lng === undefined || loc.lng === null ? null : num(loc.lng, "location.lng", { min: -180, max: 180 });
  const participating = strArray(data.participatingCampusIds, "participatingCampusIds", { optional: true, max: 20 });
  return {
    title: str(data.title, "title", { max: 120 }),
    description: str(data.description, "description", { max: 5000 }),
    clubId: str(data.clubId, "clubId"),
    posterUrl: str(data.posterUrl, "posterUrl", { optional: true, max: 2000 }),
    startAt: startAt!,
    endAt: endAt!,
    location: { name: str(loc.name, "location.name", { max: 120 }), address: str(loc.address, "location.address", { optional: true, max: 300 }), lat, lng },
    capacity: num(data.capacity, "capacity", { min: 0, max: 100000, int: true }),
    waitlistEnabled: data.waitlistEnabled === true,
    tribeIds: strArray(data.tribeIds, "tribeIds", { max: 10 }),
    tags: strArray(data.tags, "tags", { optional: true, max: 15 }).map((t) => t.toLowerCase()),
    participatingCampusIds: [...new Set([campusId, ...participating])],
    contact: str(data.contact, "contact", { optional: true, max: 200 }),
    registrationClosesAt: toDate(data.registrationClosesAt),
    certificateEnabled: data.certificateEnabled !== false,
  };
}

/** Organizer creates an event. Approved organizers publish immediately (low friction). */
export const createEvent = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const m = await requireMembership(actor, campusId, ["organizer", "campus_admin"]);
    const input = parseEventInput(req.data ?? {}, campusId);
    const publish = req.data?.publish !== false;
    if (!m.roles.includes("campus_admin") && !(m.clubIds ?? []).includes(input.clubId)) {
      fail("permission_denied", "You don't have access to this organizer account.");
    }
    if (input.tribeIds.length === 0) fail("invalid_argument", "Tag at least one Tribe so students can find this event.");
    const campus = await loadCampus(campusId);
    const flags = await featureFlags(campusId);
    if (input.participatingCampusIds.length > 1 && !flags.intercampus_events_enabled) {
      fail("feature_disabled", "Inter-campus events aren't enabled on this campus yet.");
    }
    const club = await db.collection(COL.clubs).doc(input.clubId).get();
    if (!club.exists || club.get("campusId") !== campusId) fail("not_found", "Club not found on this campus.");

    const ref = db.collection(COL.events).doc();
    const status: EventStatus = publish ? "published" : "draft";
    const e = campus.economy;
    const doc = {
      ...input,
      campusId,
      hostCampusId: campusId,
      organizerUid: actor.uid,
      clubName: club.get("name"),
      startAt: Timestamp.fromDate(input.startAt),
      endAt: Timestamp.fromDate(input.endAt),
      registrationClosesAt: input.registrationClosesAt ? Timestamp.fromDate(input.registrationClosesAt) : null,
      checkinOpensAt: Timestamp.fromMillis(input.startAt.getTime() - e.checkinOpensMinutesBefore * 60000),
      checkinClosesAt: Timestamp.fromMillis(input.endAt.getTime() + e.checkinClosesMinutesAfter * 60000),
      checkinActive: false,
      status,
      publishedAt: publish ? serverTs() : null,
      reviewStatus: publish ? "pending_review" : "n/a",
      stats: { rsvpCount: 0, waitlistCount: 0, checkinCount: 0, manualCheckinCount: 0, feedbackCount: 0, ratingSum: 0, ratingAvg: 0, opens: 0, impressions: 0 },
      tribeCheckins: {},
      tribeRsvps: {},
      organizerBonusAwarded: false,
      searchTokens: searchTokens(input.title, input.description, club.get("name"), ...input.tags),
      createdAt: serverTs(),
      updatedAt: serverTs(),
    };
    await ref.set(doc);
    await track("organizer_event_created", { uid: actor.uid, campusId, eventId: ref.id, organizerId: input.clubId, tribeIds: input.tribeIds });
    if (publish) await track("organizer_event_published", { uid: actor.uid, campusId, eventId: ref.id, organizerId: input.clubId });
    return { eventId: ref.id, status };
  }),
);

/** Update event. Significant changes (time/venue/date) notify confirmed RSVPs. */
export const updateEvent = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const ref = db.collection(COL.events).doc(eventId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found", "Event not found.");
    const ev = snap.data()!;
    const m = await requireMembership(actor, ev.campusId, ["organizer", "campus_admin"]);
    if (!canManageEvent(m, actor.uid, ev)) fail("permission_denied", "You don't have access to this event.");
    if (["cancelled", "completed", "archived"].includes(ev.status)) fail("event_not_open", "This event can no longer be edited.");
    const input = parseEventInput({ ...ev, ...req.data, startAt: req.data?.startAt ?? ev.startAt, endAt: req.data?.endAt ?? ev.endAt, clubId: ev.clubId }, ev.campusId);
    const publish = req.data?.publish === true;
    const campus = await loadCampus(ev.campusId);
    const e = campus.economy;

    const significant =
      tsToMs(ev.startAt) !== input.startAt.getTime() ||
      tsToMs(ev.endAt) !== input.endAt.getTime() ||
      ev.location?.name !== input.location.name;

    const before = { title: ev.title, startAt: tsToMs(ev.startAt), endAt: tsToMs(ev.endAt), location: ev.location?.name, capacity: ev.capacity, status: ev.status };
    const nextStatus: EventStatus = publish && ev.status === "draft" ? "published" : ev.status;
    await ref.update({
      ...input,
      clubId: ev.clubId,
      startAt: Timestamp.fromDate(input.startAt),
      endAt: Timestamp.fromDate(input.endAt),
      registrationClosesAt: input.registrationClosesAt ? Timestamp.fromDate(input.registrationClosesAt) : null,
      checkinOpensAt: Timestamp.fromMillis(input.startAt.getTime() - e.checkinOpensMinutesBefore * 60000),
      checkinClosesAt: Timestamp.fromMillis(input.endAt.getTime() + e.checkinClosesMinutesAfter * 60000),
      status: nextStatus,
      publishedAt: nextStatus === "published" && !ev.publishedAt ? serverTs() : ev.publishedAt ?? null,
      reviewStatus: nextStatus === "published" && ev.reviewStatus === "n/a" ? "pending_review" : ev.reviewStatus,
      searchTokens: searchTokens(input.title, input.description, ev.clubName, ...input.tags),
      updatedAt: serverTs(),
      lastSignificantChangeAt: significant ? serverTs() : ev.lastSignificantChangeAt ?? null,
    });
    writeAudit({ actorUid: actor.uid, action: "event.update", entityType: "event", entityId: eventId, campusId: ev.campusId, before, after: { title: input.title, startAt: input.startAt.getTime(), endAt: input.endAt.getTime(), location: input.location.name, capacity: input.capacity, status: nextStatus } });
    if (nextStatus === "published" && ev.status === "draft") {
      await track("organizer_event_published", { uid: actor.uid, campusId: ev.campusId, eventId, organizerId: ev.clubId });
    }
    if (significant && ev.status === "published") {
      await notifyRsvps(eventId, ev.campusId, {
        title: `${input.title} has changed`,
        body: `New details: ${input.location.name}, ${input.startAt.toLocaleString("en-IN", { timeZone: campus.timezone, dateStyle: "medium", timeStyle: "short" })}. Check the event for the update.`,
        keyPart: `changed:${Date.now()}`,
      });
      // Reminders are recomputed by the scheduler because startAt changed.
      await cancelNotificationsByPrefix(`reminder:${eventId}:`);
    }
    return { ok: true, status: nextStatus, notifiedRsvps: significant };
  }),
);

export const cancelEvent = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const reason = str(req.data?.reason, "reason", { max: 500 });
    const ref = db.collection(COL.events).doc(eventId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found", "Event not found.");
    const ev = snap.data()!;
    const m = await requireMembership(actor, ev.campusId, ["organizer", "campus_admin"]);
    if (!canManageEvent(m, actor.uid, ev)) fail("permission_denied", "You don't have access to this event.");
    if (ev.status === "cancelled") return { ok: true, already: true };
    if (ev.status === "completed" || ev.status === "archived") fail("event_not_open", "Completed events can't be cancelled.");
    await ref.update({ status: "cancelled", checkinActive: false, cancellation: { reason, at: serverTs(), byUid: actor.uid }, updatedAt: serverTs() });
    writeAudit({ actorUid: actor.uid, action: "event.cancel", entityType: "event", entityId: eventId, campusId: ev.campusId, reason, before: { status: ev.status }, after: { status: "cancelled" } });
    await track("organizer_event_cancelled", { uid: actor.uid, campusId: ev.campusId, eventId, organizerId: ev.clubId });
    await cancelNotificationsByPrefix(`reminder:${eventId}:`);
    await notifyRsvps(eventId, ev.campusId, { title: `${ev.title} is cancelled`, body: reason ? `Organizer's note: ${reason}` : "The organizer cancelled this event.", keyPart: "cancelled" });
    return { ok: true };
  }),
);

/** Campus admin review actions: approve, unpublish, or flag an event (post-publication queue). */
export const reviewEvent = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const decision = str(req.data?.decision, "decision") as "approved" | "unpublished" | "flagged";
    const reason = str(req.data?.reason, "reason", { optional: true, max: 500 });
    if (!["approved", "unpublished", "flagged"].includes(decision)) fail("invalid_argument", "Unknown decision.");
    const ref = db.collection(COL.events).doc(eventId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found", "Event not found.");
    const ev = snap.data()!;
    await requireMembership(actor, ev.campusId, ["campus_admin"]);
    if (decision === "unpublished" && !reason) fail("invalid_argument", "A reason is required to unpublish.");
    const update: Record<string, unknown> = { reviewStatus: decision, reviewedBy: actor.uid, reviewedAt: serverTs(), reviewReason: reason || null, updatedAt: serverTs() };
    if (decision === "unpublished") {
      update.status = "cancelled";
      update.checkinActive = false;
      update.cancellation = { reason: `Removed by campus operations: ${reason}`, at: serverTs(), byUid: actor.uid };
    }
    await ref.update(update);
    writeAudit({ actorUid: actor.uid, action: `event.review.${decision}`, entityType: "event", entityId: eventId, campusId: ev.campusId, reason, before: { status: ev.status, reviewStatus: ev.reviewStatus }, after: { status: update.status ?? ev.status, reviewStatus: decision } });
    if (decision === "unpublished") {
      await cancelNotificationsByPrefix(`reminder:${eventId}:`);
      await notifyRsvps(eventId, ev.campusId, { title: `${ev.title} has been removed`, body: "Campus operations removed this event. Any RSVP BuzzCoins you earned are yours to keep.", keyPart: "unpublished" });
    }
    return { ok: true };
  }),
);

/**
 * Close an event: finalize status, award organizer bonus once, queue feedback
 * prompts. Idempotent — repeated calls never double-award.
 */
export async function closeEventInternal(eventId: string, actorUid: string | null): Promise<{ closed: boolean; organizerBonus: number }> {
  const ref = db.collection(COL.events).doc(eventId);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) fail("not_found", "Event not found.");
    const ev = snap.data()!;
    if (ev.status === "cancelled" || ev.status === "archived") return { closed: false, organizerBonus: 0, ev };
    const campus = await loadCampus(ev.campusId, tx);
    const verified = Number(ev.stats?.checkinCount ?? 0);
    let bonus = 0;
    const key = ids.ledger.organizer(eventId);
    const exists = await ledgerEntryExists(tx, key);
    if (!ev.organizerBonusAwarded && !exists && organizerBonusEligible(campus.economy, verified)) {
      bonus = writeCredit(tx, { key, uid: ev.organizerUid, campusId: ev.campusId, type: "credit", reason: "organizer_bonus", amount: campus.economy.organizerReward, refId: eventId, economy: campus.economy, alreadyExists: false, meta: { verifiedAttendees: verified } });
    }
    tx.update(ref, {
      status: "completed",
      checkinActive: false,
      closedAt: ev.closedAt ?? serverTs(),
      closedBy: ev.closedBy ?? actorUid ?? "system",
      organizerBonusAwarded: ev.organizerBonusAwarded || bonus > 0 || exists,
      updatedAt: serverTs(),
    });
    if (actorUid) {
      writeAudit({ actorUid, action: "event.close", entityType: "event", entityId: eventId, campusId: ev.campusId, before: { status: ev.status }, after: { status: "completed", organizerBonus: bonus } }, tx);
    }
    return { closed: ev.status !== "completed", organizerBonus: bonus, ev };
  });
  if (result.closed) {
    await queueFeedbackPrompts(eventId, result.ev);
    if (result.organizerBonus > 0) await track("coins_earned", { uid: result.ev.organizerUid, campusId: result.ev.campusId, eventId, reason: "organizer_bonus", amount: result.organizerBonus });
  }
  return { closed: result.closed, organizerBonus: result.organizerBonus };
}

export const closeEvent = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const snap = await db.collection(COL.events).doc(eventId).get();
    if (!snap.exists) fail("not_found", "Event not found.");
    const ev = snap.data()!;
    const m = await requireMembership(actor, ev.campusId, ["organizer", "campus_admin"]);
    if (!canManageEvent(m, actor.uid, ev)) fail("permission_denied", "You don't have access to this event.");
    return closeEventInternal(eventId, actor.uid);
  }),
);

/** Feedback prompt ~2h after the event ends for every checked-in attendee (deduped). */
export async function queueFeedbackPrompts(eventId: string, ev: FirebaseFirestore.DocumentData): Promise<number> {
  const endMs = tsToMs(ev.endAt) ?? Date.now();
  const scheduledFor = new Date(Math.max(Date.now(), endMs + 2 * 3600000));
  let n = 0;
  await forEachPage(db.collection(COL.checkins).where("eventId", "==", eventId), 200, async (docs) => {
    for (const d of docs) {
      const r = await enqueueNotification({
        uid: d.get("uid"),
        campusId: ev.campusId,
        category: "post_event",
        title: `How was ${ev.title}?`,
        body: "Rate it in 10 seconds and earn BuzzCoins.",
        route: `/events/${eventId}/feedback`,
        scheduledFor,
        dedupeKey: `feedback:${eventId}:${d.get("uid")}`,
      });
      if (r === "queued") n++;
    }
  });
  return n;
}

async function notifyRsvps(eventId: string, campusId: string, msg: { title: string; body: string; keyPart: string }): Promise<number> {
  let n = 0;
  await forEachPage(db.collection(COL.rsvps).where("eventId", "==", eventId).where("status", "in", ["confirmed", "waitlisted"]), 200, async (docs) => {
    for (const d of docs) {
      const r = await enqueueNotification({ uid: d.get("uid"), campusId, category: "transactional", title: msg.title, body: msg.body, route: `/events/${eventId}`, dedupeKey: `event:${eventId}:${msg.keyPart}:${d.get("uid")}` });
      if (r === "queued") n++;
    }
  });
  return n;
}

/** Any campus member can report an event or a review; admins triage in the review queue. */
export const reportContent = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId);
    const entityType = str(req.data?.entityType, "entityType");
    if (!["event", "review"].includes(entityType)) fail("invalid_argument", "Unknown content type.");
    const entityId = str(req.data?.entityId, "entityId");
    const reason = str(req.data?.reason, "reason", { max: 1000 });
    const ref = db.collection(COL.reports).doc(`${entityType}:${entityId}:${actor.uid}`);
    await ref.set({ campusId, entityType, entityId, reason, reporterUid: actor.uid, status: "open", createdAt: serverTs() });
    if (entityType === "event") await db.collection(COL.events).doc(entityId).set({ reportCount: inc(1), reviewStatus: "flagged" }, { merge: true });
    return { ok: true };
  }),
);
