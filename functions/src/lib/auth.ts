import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { DomainError, DomainErrorCode, fail } from "../domain/errors";
import type { MembershipStatus, Role, UserStatus } from "../domain/types";
import { db } from "./firestore";
import { isEmulator } from "../config/secrets";

export interface Actor {
  uid: string;
  email: string | null;
  emailVerified: boolean;
  /** undefined when the user doc hasn't been created yet (mid-onboarding) */
  user?: FirebaseFirestore.DocumentData;
}

export interface MembershipDoc {
  campusId: string;
  uid: string;
  roles: Role[];
  status: MembershipStatus;
  vendorId?: string;
  brandId?: string;
  clubIds?: string[];
}

/** Require a signed-in caller. Email verification is required unless `allowUnverified`. */
export async function requireAuth(req: CallableRequest, opts: { allowUnverified?: boolean } = {}): Promise<Actor> {
  const auth = req.auth;
  if (!auth) fail("unauthenticated");
  const emailVerified = !!auth!.token.email_verified || (isEmulator() && process.env.CB_EMULATOR_SKIP_EMAIL_VERIFY === "true");
  if (!opts.allowUnverified && !emailVerified) fail("email_not_verified");
  const userSnap = await db.collection(COL.users).doc(auth!.uid).get();
  const user = userSnap.exists ? userSnap.data() : undefined;
  if (user && (user.status as UserStatus) === "suspended") fail("account_suspended");
  if (user && (user.status as UserStatus) === "deleted") fail("permission_denied", "This account has been deleted.");
  return { uid: auth!.uid, email: auth!.token.email ?? null, emailVerified, user };
}

export async function getMembership(campusId: string, uid: string): Promise<MembershipDoc | null> {
  const snap = await db.collection(COL.memberships).doc(ids.membership(campusId, uid)).get();
  if (!snap.exists) return null;
  return snap.data() as MembershipDoc;
}

export async function isSuperAdmin(uid: string): Promise<boolean> {
  const snap = await db.collection(COL.users).doc(uid).get();
  return snap.exists && snap.get("superAdmin") === true;
}

/** Require an active membership in `campusId`, optionally with one of `roles`. Super admins pass. */
export async function requireMembership(actor: Actor, campusId: string, roles?: Role[]): Promise<MembershipDoc> {
  if (!campusId) fail("invalid_argument", "campusId is required");
  const m = await getMembership(campusId, actor.uid);
  if (await isSuperAdmin(actor.uid)) {
    return m ?? { campusId, uid: actor.uid, roles: ["super_admin"], status: "active" };
  }
  if (!m) fail("not_campus_member");
  if (m!.status === "suspended") fail("account_suspended");
  if (m!.status !== "active") fail("not_campus_member", "Your campus membership is still pending.");
  if (roles && roles.length > 0 && !roles.some((r) => m!.roles.includes(r))) {
    fail("permission_denied", `Requires one of: ${roles.join(", ")}`);
  }
  return m!;
}

export async function requireSuperAdmin(actor: Actor): Promise<void> {
  if (!(await isSuperAdmin(actor.uid))) fail("permission_denied", "Super admin only.");
}

export function hasRole(m: MembershipDoc | null, role: Role): boolean {
  return !!m && m.roles.includes(role) && m.status === "active";
}

/** Organizer must own the event via club admin or be its creator (or campus admin). */
export function canManageEvent(m: MembershipDoc, uid: string, event: FirebaseFirestore.DocumentData): boolean {
  if (m.roles.includes("campus_admin") || m.roles.includes("super_admin")) return true;
  if (!m.roles.includes("organizer")) return false;
  if (event.organizerUid === uid) return true;
  return Array.isArray(m.clubIds) && m.clubIds.includes(event.clubId);
}

const CODE_MAP: Record<DomainErrorCode, HttpsError["code"]> = {
  unauthenticated: "unauthenticated",
  email_not_verified: "failed-precondition",
  campus_not_supported: "failed-precondition",
  not_campus_member: "permission-denied",
  account_suspended: "permission-denied",
  permission_denied: "permission-denied",
  not_found: "not-found",
  invalid_argument: "invalid-argument",
  event_not_open: "failed-precondition",
  event_cancelled: "failed-precondition",
  event_full: "resource-exhausted",
  already_rsvped: "already-exists",
  rsvp_closed: "failed-precondition",
  checkin_not_active: "failed-precondition",
  checkin_window_closed: "failed-precondition",
  qr_expired: "deadline-exceeded",
  qr_invalid: "invalid-argument",
  already_checked_in: "already-exists",
  rsvp_required: "failed-precondition",
  feedback_requires_checkin: "failed-precondition",
  already_submitted: "already-exists",
  insufficient_coins: "failed-precondition",
  reward_inactive: "failed-precondition",
  reward_out_of_stock: "resource-exhausted",
  reward_limit_reached: "resource-exhausted",
  redemption_invalid: "failed-precondition",
  referral_invalid: "invalid-argument",
  self_referral: "failed-precondition",
  already_referred: "already-exists",
  feature_disabled: "unavailable",
  quest_not_live: "failed-precondition",
  quest_full: "resource-exhausted",
  quest_not_eligible: "failed-precondition",
  notification_cap_exceeded: "resource-exhausted",
  conflict: "aborted",
  internal: "internal",
};

/** Wrap a handler so DomainErrors become structured HttpsErrors (code preserved in details). */
export function callableHandler<TReq, TRes>(fn: (req: CallableRequest<TReq>) => Promise<TRes>) {
  return async (req: CallableRequest<TReq>): Promise<TRes> => {
    try {
      return await fn(req);
    } catch (e) {
      if (e instanceof DomainError) {
        throw new HttpsError(CODE_MAP[e.code], e.message, { code: e.code, ...(e.details ?? {}) });
      }
      if (e instanceof HttpsError) throw e;
      console.error("Unhandled error in callable", e);
      throw new HttpsError("internal", "Something went wrong on our side. Please try again.", { code: "internal" });
    }
  };
}

export function str(v: unknown, name: string, opts: { max?: number; optional?: boolean } = {}): string {
  if (v === undefined || v === null || v === "") {
    if (opts.optional) return "";
    fail("invalid_argument", `${name} is required`);
  }
  if (typeof v !== "string") fail("invalid_argument", `${name} must be a string`);
  const s = (v as string).trim();
  if (opts.max && s.length > opts.max) fail("invalid_argument", `${name} is too long`);
  return s;
}

export function num(v: unknown, name: string, opts: { min?: number; max?: number; optional?: boolean; int?: boolean } = {}): number {
  if (v === undefined || v === null) {
    if (opts.optional) return 0;
    fail("invalid_argument", `${name} is required`);
  }
  const n = Number(v);
  if (!Number.isFinite(n)) fail("invalid_argument", `${name} must be a number`);
  if (opts.int && !Number.isInteger(n)) fail("invalid_argument", `${name} must be an integer`);
  if (opts.min !== undefined && n < opts.min) fail("invalid_argument", `${name} must be ≥ ${opts.min}`);
  if (opts.max !== undefined && n > opts.max) fail("invalid_argument", `${name} must be ≤ ${opts.max}`);
  return n;
}

export function strArray(v: unknown, name: string, opts: { max?: number; optional?: boolean } = {}): string[] {
  if (v === undefined || v === null) {
    if (opts.optional) return [];
    fail("invalid_argument", `${name} is required`);
  }
  if (!Array.isArray(v) || !v.every((x) => typeof x === "string")) fail("invalid_argument", `${name} must be a string list`);
  const arr = (v as string[]).map((s) => s.trim()).filter(Boolean);
  if (opts.max && arr.length > opts.max) fail("invalid_argument", `${name} has too many entries`);
  return [...new Set(arr)];
}
