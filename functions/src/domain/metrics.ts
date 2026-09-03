/** Tested core-metric formulas. Inputs are already-aggregated counts. */

export function percent(numerator: number, denominator: number): number {
  if (denominator <= 0) return 0;
  return round2((numerator / denominator) * 100);
}

export const round2 = (n: number) => Math.round(n * 100) / 100;

/** WAP = unique users with ≥1 verified check-in in the week. */
export function weeklyActiveParticipants(checkinsInWeek: Array<{ uid: string }>): number {
  return new Set(checkinsInWeek.map((c) => c.uid)).size;
}

export function wapRatio(wap: number, registered: number): number {
  return percent(wap, registered);
}

export function rsvpToAttendance(verifiedCheckins: number, rsvps: number): number {
  return percent(verifiedCheckins, rsvps);
}

export function discoveryConversion(rsvps: number, uniqueOpens: number): number {
  return percent(rsvps, uniqueOpens);
}

export interface RedemptionRates {
  byCoins: number;
  byUsers: number;
}

export function redemptionRates(input: {
  coinsRedeemed: number;
  coinsEarned: number;
  usersRedeemed: number;
  usersEarned: number;
}): RedemptionRates {
  return {
    byCoins: percent(input.coinsRedeemed, input.coinsEarned),
    byUsers: percent(input.usersRedeemed, input.usersEarned),
  };
}

/** NPS: promoters 9–10, passives 7–8, detractors 0–6. */
export function nps(scores: number[]): { nps: number; promoters: number; passives: number; detractors: number; responses: number } {
  const valid = scores.filter((s) => Number.isFinite(s) && s >= 0 && s <= 10);
  const responses = valid.length;
  const promoters = valid.filter((s) => s >= 9).length;
  const detractors = valid.filter((s) => s <= 6).length;
  const passives = responses - promoters - detractors;
  const value = responses === 0 ? 0 : Math.round((promoters / responses) * 100 - (detractors / responses) * 100);
  return { nps: value, promoters, passives, detractors, responses };
}

export function wouldMissPercent(answers: Array<"yes" | "strongly_yes" | "no" | "unsure">): number {
  const yes = answers.filter((a) => a === "yes" || a === "strongly_yes").length;
  return percent(yes, answers.length);
}

/**
 * Week-6 retention for a Week-1 cohort.
 *  - product retention: cohort members with any qualifying activity in week 6
 *  - participation retention: cohort members with a verified check-in in week 6
 */
export function week6Retention(input: {
  cohortUids: string[];
  activeWeek6Uids: string[];
  checkedInWeek6Uids: string[];
}): { product: number; participation: number; cohortSize: number } {
  const cohort = new Set(input.cohortUids);
  const active = input.activeWeek6Uids.filter((u) => cohort.has(u)).length;
  const attended = input.checkedInWeek6Uids.filter((u) => cohort.has(u)).length;
  return {
    product: percent(active, cohort.size),
    participation: percent(attended, cohort.size),
    cohortSize: cohort.size,
  };
}

export function organizerSupplyHealth(input: {
  organizersPostingThisWeek: number;
  eventsPostedThisWeek: number;
  eventsNext7Days: number;
  eventsTodayTomorrow: number;
  weeklyEventsTarget: number;
  minEventsTodayTomorrow: number;
}): { flags: string[] } {
  const flags: string[] = [];
  if (input.eventsNext7Days === 0) flags.push("no_upcoming_events");
  if (input.eventsTodayTomorrow < input.minEventsTodayTomorrow) flags.push("empty_feed_risk");
  if (input.eventsPostedThisWeek < input.weeklyEventsTarget) flags.push("below_weekly_event_target");
  return { flags };
}

export function repeatAttendeeRate(attendeeEventCounts: number[]): number {
  const total = attendeeEventCounts.length;
  const repeat = attendeeEventCounts.filter((c) => c >= 2).length;
  return percent(repeat, total);
}
