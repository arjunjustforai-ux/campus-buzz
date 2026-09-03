import { onCall } from "firebase-functions/v2/https";
import { COL } from "../config/collections";
import { DEFAULT_RECOMMENDATION_WEIGHTS } from "../config/defaults";
import { feedVariantFor, rankEvents } from "../domain/recommendation";
import { localParts } from "../domain/time";
import type { EventForRanking, RecommendationWeights } from "../domain/types";
import { track } from "../lib/analytics";
import { callableHandler, requireAuth, requireMembership, str } from "../lib/auth";
import { featureFlags, loadCampus } from "../lib/campus";
import { db, Timestamp, tsToMs } from "../lib/firestore";
import { callableOpts } from "../lib/options";

/**
 * Personalized feed: returns ranked event ids + reason codes for the next 14 days.
 * The client always has a chronological fallback; this never returns an empty
 * list when events exist.
 */
export const getRecommendedFeed = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId") || (actor.user?.activeCampusId as string);
    await requireMembership(actor, campusId);
    const flags = await featureFlags(campusId);
    const campus = await loadCampus(campusId);
    const variant = flags.personalized_feed_enabled ? (actor.user?.feedVariant ?? feedVariantFor(actor.uid)) : "chronological";
    const now = new Date();
    const events = await db
      .collection(COL.events)
      .where("participatingCampusIds", "array-contains", campusId)
      .where("status", "==", "published")
      .where("startAt", ">=", Timestamp.fromDate(now))
      .where("startAt", "<=", Timestamp.fromMillis(now.getTime() + 14 * 86400000))
      .orderBy("startAt")
      .limit(100)
      .get();
    if (variant === "chronological" || events.empty) {
      return { variant, items: events.docs.map((d) => ({ eventId: d.id, score: 0, reasons: [] })) };
    }
    const weightsSnap = await db.collection(COL.featureConfigs).doc(campusId).get();
    const weights: RecommendationWeights = { ...DEFAULT_RECOMMENDATION_WEIGHTS, ...(weightsSnap.get("recommendationWeights") ?? {}) };
    const stats = await db.collection(COL.participationStats).doc(actor.uid).get();
    // Friends' RSVPs (only friends who opted in to activity visibility).
    let friendUids: string[] = [];
    if (flags.friends_enabled) {
      const fs = await db.collection(COL.friendships).where("uids", "array-contains", actor.uid).where("status", "==", "accepted").get();
      const others = fs.docs.map((d) => (d.get("uids") as string[]).find((u) => u !== actor.uid)!).filter(Boolean);
      if (others.length > 0) {
        const users = await db.getAll(...others.slice(0, 50).map((u) => db.collection(COL.users).doc(u)));
        friendUids = users.filter((u) => u.exists && u.get("privacy.showActivityToFriends") === true).map((u) => u.id);
      }
    }
    const friendRsvpCounts = new Map<string, number>();
    if (friendUids.length > 0) {
      const rs = await db.collection(COL.rsvps).where("uid", "in", friendUids.slice(0, 30)).where("status", "==", "confirmed").where("startAt", ">=", Timestamp.fromDate(now)).select("eventId").get();
      rs.docs.forEach((d) => friendRsvpCounts.set(d.get("eventId"), (friendRsvpCounts.get(d.get("eventId")) ?? 0) + 1));
    }
    const forRanking: EventForRanking[] = events.docs.map((d) => {
      const startMs = tsToMs(d.get("startAt"))!;
      const lp = localParts(new Date(startMs), campus.timezone);
      return { eventId: d.id, tribeIds: d.get("tribeIds") ?? [], tags: d.get("tags") ?? [], startAtMs: startMs, rsvpCount: d.get("stats.rsvpCount") ?? 0, friendRsvpCount: friendRsvpCounts.get(d.id) ?? 0, weekday: lp.weekday, hour: lp.hour };
    });
    const ranked = rankEvents(forRanking, { tribeIds: actor.user?.tribeIds ?? [], attendedTags: stats.get("attendedTags") ?? {}, attendedWeekdays: stats.get("attendedWeekdays") ?? {}, attendedHourBuckets: stats.get("attendedHourBuckets") ?? {} }, weights, now.getTime());
    await track("feed_viewed", { uid: actor.uid, campusId, feedVariant: variant, count: ranked.length });
    return { variant, items: ranked };
  }),
);
