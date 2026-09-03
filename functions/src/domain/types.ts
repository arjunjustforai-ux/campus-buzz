/**
 * Shared domain types. Pure TypeScript — no Firebase imports so they can be used by
 * unit tests and mirrored in the Flutter models.
 */

export type Role =
  | "student"
  | "organizer"
  | "ambassador"
  | "campus_admin"
  | "brand"
  | "vendor"
  | "super_admin";

export const ALL_ROLES: Role[] = [
  "student",
  "organizer",
  "ambassador",
  "campus_admin",
  "brand",
  "vendor",
  "super_admin",
];

export type UserStatus = "active" | "suspended" | "deleted";
export type MembershipStatus = "active" | "pending" | "suspended";

export type EventStatus = "draft" | "published" | "cancelled" | "completed" | "archived";
export type RsvpStatus = "confirmed" | "waitlisted" | "cancelled";
export type CheckinMethod = "qr" | "manual";

export type LedgerType = "credit" | "debit" | "expiry" | "adjustment";
export type LedgerReason =
  | "rsvp"
  | "checkin"
  | "feedback"
  | "referral"
  | "organizer_bonus"
  | "quest"
  | "redemption"
  | "expiry"
  | "admin_adjustment"
  | "redemption_refund";

export type RewardType =
  | "voucher"
  | "printing_credit"
  | "priority_access"
  | "merchandise"
  | "certificate"
  | "generic";

export type RedemptionStatus = "issued" | "fulfilled" | "expired" | "cancelled";
export type SettlementStatus = "pending" | "settled";

export type QuestStatus =
  | "draft"
  | "submitted"
  | "approved"
  | "live"
  | "paused"
  | "completed"
  | "cancelled";

export type QuestType =
  | "event_attendance"
  | "qr_activation"
  | "event_count"
  | "checklist"
  | "streak";

export type CampaignFinancialStatus =
  | "quoted"
  | "approved"
  | "advance_pending"
  | "advance_received"
  | "live"
  | "completed"
  | "final_payment_pending"
  | "paid";

export type NotificationCategory = "transactional" | "reminder" | "engagement" | "post_event";

export type FeedVariant = "chronological" | "personalized";

export type EntitlementKey =
  | "organizer_basic"
  | "organizer_premium"
  | "campus_analytics"
  | "brand_dashboard"
  | "super_admin";

export interface EconomyConfig {
  version: number;
  rsvpReward: number;
  checkinReward: number;
  feedbackReward: number;
  referralReward: number;
  organizerReward: number;
  organizerMinVerifiedAttendees: number;
  streakThresholdWeeks: number;
  streakMultiplier: number;
  coinExpiryDays: number;
  engagementNotificationCapPerDay: number;
  checkinOpensMinutesBefore: number;
  checkinClosesMinutesAfter: number;
  manualCorrectionWindowHours: number;
  /** ISO string or null → immediately effective */
  effectiveAt: string | null;
  description: string;
}

export interface FeatureFlags {
  discovery_enabled: boolean;
  search_enabled: boolean;
  tribes_enabled: boolean;
  buzzcoins_enabled: boolean;
  qr_checkin_enabled: boolean;
  rewards_enabled: boolean;
  streaks_enabled: boolean;
  tribe_leaderboard_enabled: boolean;
  referrals_enabled: boolean;
  friends_enabled: boolean;
  personalized_feed_enabled: boolean;
  reviews_enabled: boolean;
  social_proof_enabled: boolean;
  campus_buzz_score_enabled: boolean;
  brand_quests_enabled: boolean;
  brand_dashboard_enabled: boolean;
  intercampus_events_enabled: boolean;
  premium_organizer_enabled: boolean;
  institutional_analytics_enabled: boolean;
  talent_profile_enabled: boolean;
}

export interface ScorecardBand {
  /** below red → Red */
  red: number;
  /** at/above green → Green; between → Yellow */
  green: number;
  unit: "count" | "percent" | "score";
}

export interface PilotConfig {
  targets: {
    registrations: number;
    organizersMin: number;
    organizersMax: number;
    wapPercent: number;
    initialEventSupply: number;
    redemptionOptionsBeforeLaunch: number;
    weeklyEventsTarget: number;
    minEventsTodayTomorrow: number;
  };
  bands: {
    registeredStudents: ScorecardBand;
    wapPercent: ScorecardBand;
    week6Retention: ScorecardBand;
    organizersPostingWeekly: ScorecardBand;
    rsvpToAttendance: ScorecardBand;
    nps: ScorecardBand;
    wouldMiss: ScorecardBand;
  };
  economyHealth: {
    weeklyEarnHealthyMin: number;
    weeklyEarnHealthyMax: number;
    weeklyEarnWarning: number;
    redemptionHealthyMin: number;
    redemptionHealthyMax: number;
    redemptionWarning: number;
    maxEarnedToRedeemableRatio: number;
  };
}

export interface RecommendationWeights {
  tribeAffinity: number;
  categoryAffinity: number;
  friendAttendance: number;
  preferredDayTime: number;
  urgency: number;
  popularity: number;
}

export type ReasonCode =
  | "because_of_tribe"
  | "similar_to_attended"
  | "friends_attending"
  | "popular_on_campus"
  | "happening_soon";

export interface RankedEvent {
  eventId: string;
  score: number;
  reasons: ReasonCode[];
}

/** Minimal event projection needed for ranking. */
export interface EventForRanking {
  eventId: string;
  tribeIds: string[];
  tags: string[];
  startAtMs: number;
  rsvpCount: number;
  friendRsvpCount: number;
  /** 0-6, local campus weekday */
  weekday: number;
  /** local campus hour 0-23 */
  hour: number;
}

export interface UserSignals {
  tribeIds: string[];
  /** category/tag → attended count */
  attendedTags: Record<string, number>;
  /** weekday → attended count */
  attendedWeekdays: Record<string, number>;
  /** hour bucket ("morning"|"afternoon"|"evening") → count */
  attendedHourBuckets: Record<string, number>;
}

export interface QrTokenPayload {
  /** event id */
  e: string;
  /** campus id */
  c: string;
  /** window index = floor(epochSeconds / rotationSeconds) */
  w: number;
  /** session nonce (rotates when organizer restarts check-in) */
  n: string;
  /** token format version */
  v: number;
}

export interface StreakState {
  /** consecutive campus-weeks with ≥1 verified check-in */
  streak: number;
  /** ISO week key of last verified participation e.g. "2026-W36" */
  lastWeekKey: string | null;
  multiplierActive: boolean;
}

export interface LedgerCredit {
  key: string;
  amount: number;
  /** remaining un-consumed portion (for FIFO expiry) */
  remaining: number;
  createdAtMs: number;
  expiresAtMs: number | null;
}

export interface LedgerEntryInput {
  key: string;
  uid: string;
  campusId: string;
  type: LedgerType;
  reason: LedgerReason;
  /** positive for credit, negative for debit/expiry */
  amount: number;
  refId?: string;
  meta?: Record<string, unknown>;
}
