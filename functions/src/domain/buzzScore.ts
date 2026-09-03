import { DEFAULT_BUZZ_SCORE_WEIGHTS } from "../config/defaults";

export interface BuzzScoreInput {
  wapPercent: number; // 0-100
  rsvpToAttendance: number; // 0-100
  eventsThisWeek: number;
  weeklyEventsTarget: number;
  retentionPercent: number; // 0-100
}

export interface BuzzScoreComponent {
  key: keyof typeof DEFAULT_BUZZ_SCORE_WEIGHTS;
  normalized: number; // 0-1
  weight: number;
  contribution: number; // 0-100 points
}

/**
 * Campus Buzz Score (0–100) = Σ weight_i × normalized_i × 100.
 * normalized: wap = wap%/100 (capped at 1 when ≥ 50%), conversion = %/100,
 * supply = eventsThisWeek / target (cap 1), retention = %/100.
 * This is an explicit configurable weighted score, not an accreditation metric.
 */
export function campusBuzzScore(
  input: BuzzScoreInput,
  weights: typeof DEFAULT_BUZZ_SCORE_WEIGHTS = DEFAULT_BUZZ_SCORE_WEIGHTS,
): { score: number; components: BuzzScoreComponent[] } {
  const cap = (n: number) => Math.max(0, Math.min(1, n));
  const norm = {
    wap: cap(input.wapPercent / 50),
    rsvpToAttendance: cap(input.rsvpToAttendance / 100),
    eventSupply: cap(input.weeklyEventsTarget > 0 ? input.eventsThisWeek / input.weeklyEventsTarget : 0),
    retention: cap(input.retentionPercent / 100),
  };
  const components = (Object.keys(weights) as Array<keyof typeof weights>).map((key) => ({
    key,
    normalized: Math.round(norm[key] * 1000) / 1000,
    weight: weights[key],
    contribution: Math.round(norm[key] * weights[key] * 100 * 10) / 10,
  }));
  const score = Math.round(components.reduce((s, c) => s + c.contribution, 0));
  return { score, components };
}
