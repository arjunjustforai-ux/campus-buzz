/** Domain error codes map 1:1 to user-facing copy in the Flutter app. */
export type DomainErrorCode =
  | "unauthenticated"
  | "email_not_verified"
  | "campus_not_supported"
  | "not_campus_member"
  | "account_suspended"
  | "permission_denied"
  | "not_found"
  | "invalid_argument"
  | "event_not_open"
  | "event_cancelled"
  | "event_full"
  | "already_rsvped"
  | "rsvp_closed"
  | "checkin_not_active"
  | "checkin_window_closed"
  | "qr_expired"
  | "qr_invalid"
  | "already_checked_in"
  | "rsvp_required"
  | "feedback_requires_checkin"
  | "already_submitted"
  | "insufficient_coins"
  | "reward_inactive"
  | "reward_out_of_stock"
  | "reward_limit_reached"
  | "redemption_invalid"
  | "referral_invalid"
  | "self_referral"
  | "already_referred"
  | "feature_disabled"
  | "quest_not_live"
  | "quest_full"
  | "quest_not_eligible"
  | "notification_cap_exceeded"
  | "conflict"
  | "internal";

export class DomainError extends Error {
  constructor(
    public readonly code: DomainErrorCode,
    message?: string,
    public readonly details?: Record<string, unknown>,
  ) {
    super(message ?? code);
    this.name = "DomainError";
  }
}

export function fail(code: DomainErrorCode, message?: string, details?: Record<string, unknown>): never {
  throw new DomainError(code, message, details);
}
