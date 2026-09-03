import type { EconomyConfig, FeatureFlags, PilotConfig, RecommendationWeights } from "../domain/types";

/**
 * Economy defaults. Every value is overridable per campus in
 * `campuses/{id}.economy` (versioned). These are NOT feature flags.
 */
export const DEFAULT_ECONOMY: EconomyConfig = {
  version: 1,
  rsvpReward: 5,
  checkinReward: 20,
  feedbackReward: 10,
  referralReward: 25,
  organizerReward: 50,
  organizerMinVerifiedAttendees: 10,
  streakThresholdWeeks: 3,
  streakMultiplier: 2,
  coinExpiryDays: 90,
  engagementNotificationCapPerDay: 2,
  checkinOpensMinutesBefore: 30,
  checkinClosesMinutesAfter: 120,
  manualCorrectionWindowHours: 48,
  effectiveAt: null,
  description: "Initial CampusBuzz economy",
};

/** Feature flag defaults (safe local fallbacks when Remote Config is unavailable). */
export const DEFAULT_FEATURE_FLAGS: FeatureFlags = {
  discovery_enabled: true,
  search_enabled: true,
  tribes_enabled: true,
  buzzcoins_enabled: true,
  qr_checkin_enabled: true,
  rewards_enabled: true,
  streaks_enabled: true,
  tribe_leaderboard_enabled: true,
  referrals_enabled: true,
  friends_enabled: true,
  personalized_feed_enabled: true,
  reviews_enabled: true,
  social_proof_enabled: true,
  campus_buzz_score_enabled: true,
  brand_quests_enabled: true,
  brand_dashboard_enabled: true,
  intercampus_events_enabled: false,
  premium_organizer_enabled: true,
  institutional_analytics_enabled: true,
  talent_profile_enabled: false,
};

/** JAGSoM pilot defaults — thresholds are configurable per campus. */
export const DEFAULT_PILOT: PilotConfig = {
  targets: {
    registrations: 150,
    organizersMin: 10,
    organizersMax: 15,
    wapPercent: 30,
    initialEventSupply: 12,
    redemptionOptionsBeforeLaunch: 3,
    weeklyEventsTarget: 8,
    minEventsTodayTomorrow: 2,
  },
  bands: {
    registeredStudents: { red: 75, green: 150, unit: "count" },
    wapPercent: { red: 15, green: 30, unit: "percent" },
    week6Retention: { red: 25, green: 45, unit: "percent" },
    organizersPostingWeekly: { red: 5, green: 10, unit: "count" },
    rsvpToAttendance: { red: 25, green: 40, unit: "percent" },
    nps: { red: 20, green: 40, unit: "score" },
    wouldMiss: { red: 20, green: 50, unit: "percent" },
  },
  economyHealth: {
    weeklyEarnHealthyMin: 30,
    weeklyEarnHealthyMax: 60,
    weeklyEarnWarning: 80,
    redemptionHealthyMin: 25,
    redemptionHealthyMax: 45,
    redemptionWarning: 15,
    maxEarnedToRedeemableRatio: 3,
  },
};

export const DEFAULT_RECOMMENDATION_WEIGHTS: RecommendationWeights = {
  tribeAffinity: 3.0,
  categoryAffinity: 2.0,
  friendAttendance: 1.5,
  preferredDayTime: 1.0,
  urgency: 1.5,
  popularity: 1.0,
};

/** Campus Buzz Score weights — documented in docs/ANALYTICS.md. Sum = 1. */
export const DEFAULT_BUZZ_SCORE_WEIGHTS = {
  wap: 0.4,
  rsvpToAttendance: 0.2,
  eventSupply: 0.2,
  retention: 0.2,
} as const;

/** Rotating QR token parameters. */
export const QR_TOKEN = {
  rotationSeconds: 30,
  graceSeconds: 15,
  version: 1,
} as const;

/** Minimum group size before Tribe/campus breakdowns are shown to brands. */
export const BRAND_MIN_GROUP_SIZE = 5;

export const REDEMPTION_CODE_TTL_DAYS = 30;
