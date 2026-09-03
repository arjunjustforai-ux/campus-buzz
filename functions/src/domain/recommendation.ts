import { hourBucket } from "./time";
import type { EventForRanking, RankedEvent, ReasonCode, RecommendationWeights, UserSignals } from "./types";

/**
 * Explainable rules-based ranking. Deterministic, weights configurable, every
 * contribution produces a reason code. Replaceable by an ML service later.
 */
export function rankEvents(
  events: EventForRanking[],
  user: UserSignals,
  weights: RecommendationWeights,
  nowMs: number,
): RankedEvent[] {
  const maxRsvp = Math.max(1, ...events.map((e) => e.rsvpCount));
  const totalAttended = Object.values(user.attendedTags).reduce((a, b) => a + b, 0);
  const totalWeekdays = Object.values(user.attendedWeekdays).reduce((a, b) => a + b, 0);
  const totalBuckets = Object.values(user.attendedHourBuckets).reduce((a, b) => a + b, 0);

  const ranked = events.map((ev) => {
    let score = 0;
    const reasons: ReasonCode[] = [];

    // Tribe affinity: fraction of the event's tribes the user belongs to.
    const tribeMatches = ev.tribeIds.filter((t) => user.tribeIds.includes(t)).length;
    if (tribeMatches > 0) {
      score += weights.tribeAffinity * (tribeMatches / Math.max(1, ev.tribeIds.length));
      reasons.push("because_of_tribe");
    }

    // Category affinity from attended tags.
    if (totalAttended > 0) {
      const affinity = [...ev.tags, ...ev.tribeIds].reduce((s, t) => s + (user.attendedTags[t] ?? 0), 0) / totalAttended;
      if (affinity > 0) {
        score += weights.categoryAffinity * Math.min(1, affinity);
        reasons.push("similar_to_attended");
      }
    }

    // Friends attending.
    if (ev.friendRsvpCount > 0) {
      score += weights.friendAttendance * Math.min(1, ev.friendRsvpCount / 3);
      reasons.push("friends_attending");
    }

    // Preferred day/time.
    if (totalWeekdays > 0 || totalBuckets > 0) {
      const dayPref = totalWeekdays > 0 ? (user.attendedWeekdays[String(ev.weekday)] ?? 0) / totalWeekdays : 0;
      const bucketPref = totalBuckets > 0 ? (user.attendedHourBuckets[hourBucket(ev.hour)] ?? 0) / totalBuckets : 0;
      score += weights.preferredDayTime * ((dayPref + bucketPref) / 2);
    }

    // Urgency: events within 48h get a boost that decays linearly; past events excluded upstream.
    const hoursAway = (ev.startAtMs - nowMs) / 3600000;
    if (hoursAway >= 0 && hoursAway <= 48) {
      score += weights.urgency * (1 - hoursAway / 48);
      reasons.push("happening_soon");
    }

    // Popularity relative to the current feed.
    const pop = ev.rsvpCount / maxRsvp;
    if (ev.rsvpCount >= 5 && pop >= 0.5) reasons.push("popular_on_campus");
    score += weights.popularity * pop;

    return { eventId: ev.eventId, score: Math.round(score * 1000) / 1000, reasons };
  });

  // Stable sort: score desc, then soonest first.
  const startById = new Map(events.map((e) => [e.eventId, e.startAtMs]));
  return ranked.sort((a, b) => b.score - a.score || (startById.get(a.eventId)! - startById.get(b.eventId)!));
}

/** Deterministic A/B assignment from uid so users keep their variant. */
export function feedVariantFor(uid: string, personalizedShare = 0.5): "chronological" | "personalized" {
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 31 + uid.charCodeAt(i)) >>> 0;
  return (h % 1000) / 1000 < personalizedShare ? "personalized" : "chronological";
}
