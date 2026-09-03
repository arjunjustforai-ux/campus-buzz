import { isoWeekKey, weeksBetween } from "./time";
import type { EconomyConfig, StreakState } from "./types";

export const EMPTY_STREAK: StreakState = { streak: 0, lastWeekKey: null, multiplierActive: false };

/**
 * Deterministic streak update on a verified check-in.
 *  - same week as last participation → unchanged
 *  - exactly next week → streak + 1
 *  - gap of ≥ 1 full week → reset to 1
 * Multiplier becomes active from `streakThresholdWeeks` onward.
 */
export function updateStreak(
  state: StreakState,
  checkinAt: Date,
  timeZone: string,
  config: Pick<EconomyConfig, "streakThresholdWeeks">,
): StreakState {
  const weekKey = isoWeekKey(checkinAt, timeZone);
  let streak: number;
  if (!state.lastWeekKey) {
    streak = 1;
  } else {
    const diff = weeksBetween(state.lastWeekKey, weekKey);
    if (diff === 0) streak = Math.max(state.streak, 1);
    else if (diff === 1) streak = state.streak + 1;
    else if (diff < 0) streak = state.streak; // out-of-order backfill; never regress
    else streak = 1;
  }
  const lastWeekKey = state.lastWeekKey && weeksBetween(state.lastWeekKey, weekKey) < 0 ? state.lastWeekKey : weekKey;
  return { streak, lastWeekKey, multiplierActive: streak >= config.streakThresholdWeeks };
}

/**
 * Whether the multiplier should apply to THIS check-in. The rule: the multiplier
 * unlocks once the streak reaches the threshold, so the check-in that completes
 * week N (N ≥ threshold) is already rewarded at 2x.
 */
export function multiplierAppliesForCheckin(next: StreakState, config: Pick<EconomyConfig, "streakThresholdWeeks">): boolean {
  return next.streak >= config.streakThresholdWeeks;
}

/** Streak as seen "now": a streak is broken if a full week was missed since last participation. */
export function effectiveStreak(state: StreakState, now: Date, timeZone: string): number {
  if (!state.lastWeekKey) return 0;
  const diff = weeksBetween(state.lastWeekKey, isoWeekKey(now, timeZone));
  return diff <= 1 ? state.streak : 0;
}
