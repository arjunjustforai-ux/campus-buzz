import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { fail } from "../domain/errors";
import { referralCodeFor } from "../domain/search";
import { feedVariantFor } from "../domain/recommendation";
import type { Role } from "../domain/types";
import { track } from "../lib/analytics";
import { writeAudit } from "../lib/audit";
import { callableHandler, isSuperAdmin, requireAuth, requireMembership, requireSuperAdmin, str, strArray } from "../lib/auth";
import { loadCampus, resolveCampusByEmail } from "../lib/campus";
import { db, FieldValue, serverTs } from "../lib/firestore";
import { callableOpts } from "../lib/options";

/** Public (auth optional): tells the registration screen whether an email belongs to a supported campus. */
export const resolveCampusForEmail = onCall(
  { ...callableOpts, enforceAppCheck: false },
  callableHandler(async (req) => {
    const email = str(req.data?.email, "email", { max: 254 }).toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) fail("invalid_argument", "Enter a valid email address.");
    const campus = await resolveCampusByEmail(email);
    if (!campus) return { supported: false };
    return { supported: true, campusId: campus.id, campusName: campus.name, timezone: campus.timezone };
  }),
);

/**
 * Creates the user profile + campus membership after email verification and
 * onboarding. Idempotent: re-running updates tribes/prefs without duplicating.
 */
export const completeOnboarding = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const email = (actor.email ?? "").toLowerCase();
    const campus = await resolveCampusByEmail(email);
    if (!campus) fail("campus_not_supported", "Your college email isn't on a supported campus yet.");
    const displayName = str(req.data?.displayName, "displayName", { max: 80 });
    const tribeIds = strArray(req.data?.tribeIds, "tribeIds", { max: 12 });
    if (tribeIds.length < 3) fail("invalid_argument", "Pick at least 3 Tribes.");
    const primaryTribeId = str(req.data?.primaryTribeId, "primaryTribeId", { optional: true }) || tribeIds[0];
    if (!tribeIds.includes(primaryTribeId)) fail("invalid_argument", "Primary Tribe must be one of your Tribes.");
    if (req.data?.consentAccepted !== true) fail("invalid_argument", "You need to accept the Terms and Privacy Policy.");
    const referralCode = str(req.data?.referralCode, "referralCode", { optional: true, max: 16 }).toUpperCase();
    const prefs = req.data?.notificationPrefs ?? {};

    // Validate tribes belong to campus.
    const tribeSnap = await db.collection(COL.tribes).where("campusId", "==", campus!.id).get();
    const validTribes = new Set(tribeSnap.docs.map((d) => d.id));
    if (!tribeIds.every((t) => validTribes.has(t))) fail("invalid_argument", "One of the selected Tribes is not available on your campus.");

    const userRef = db.collection(COL.users).doc(actor.uid);
    const memberRef = db.collection(COL.memberships).doc(ids.membership(campus!.id, actor.uid));
    const isNew = await db.runTransaction(async (tx) => {
      const [userSnap, memberSnap] = await Promise.all([tx.get(userRef), tx.get(memberRef)]);
      const created = !userSnap.exists;
      const base = {
        uid: actor.uid,
        email,
        displayName,
        avatarUrl: userSnap.get("avatarUrl") ?? null,
        activeCampusId: campus!.id,
        campusIds: [campus!.id],
        tribeIds,
        primaryTribeId,
        onboardingCompleted: true,
        consentAcceptedAt: userSnap.get("consentAcceptedAt") ?? serverTs(),
        notificationPrefs: {
          transactional: true,
          reminders: prefs.reminders !== false,
          engagement: prefs.engagement !== false,
          postEvent: prefs.postEvent !== false,
        },
        privacy: {
          showActivityToFriends: userSnap.get("privacy.showActivityToFriends") ?? false,
          talentProfileOptIn: false,
          anonymousFeedback: userSnap.get("privacy.anonymousFeedback") ?? false,
        },
        status: userSnap.get("status") ?? "active",
        referralCode: userSnap.get("referralCode") ?? referralCodeFor(actor.uid, displayName),
        feedVariant: userSnap.get("feedVariant") ?? feedVariantFor(actor.uid),
        emailVerifiedAt: userSnap.get("emailVerifiedAt") ?? serverTs(),
        updatedAt: serverTs(),
        ...(created ? { createdAt: serverTs(), superAdmin: false } : {}),
      };
      tx.set(userRef, base, { merge: true });
      if (!memberSnap.exists) {
        tx.set(memberRef, {
          campusId: campus!.id,
          uid: actor.uid,
          roles: ["student"] as Role[],
          status: "active",
          clubIds: [],
          requestedRoles: [],
          joinedAt: serverTs(),
          displayName,
          tribeIds,
        });
      } else {
        tx.update(memberRef, { displayName, tribeIds });
      }
      tx.set(db.collection(COL.participationStats).doc(actor.uid), { uid: actor.uid, campusId: campus!.id, streak: 0, lastWeekKey: null, multiplierActive: false, totalCheckins: 0, totalRsvps: 0, attendedTags: {}, attendedWeekdays: {}, attendedHourBuckets: {}, updatedAt: serverTs() }, { merge: true });
      tx.set(db.collection(COL.coinBalances).doc(actor.uid), { uid: actor.uid, campusId: campus!.id, balance: 0, lifetimeEarned: 0, lifetimeRedeemed: 0, lifetimeExpired: 0, updatedAt: serverTs() }, { merge: true });
      return created;
    });

    if (isNew) {
      await track("registration_completed", { uid: actor.uid, campusId: campus!.id, role: "student" });
      await track("onboarding_completed", { uid: actor.uid, campusId: campus!.id, tribeIds });
    }
    let referral: "applied" | "invalid" | "skipped" = "skipped";
    if (referralCode && isNew) {
      referral = await applyReferralInternal(actor.uid, campus!.id, referralCode);
    }
    return { campusId: campus!.id, isNew, referral };
  }),
);

/** Shared by completeOnboarding and the applyReferral callable. */
export async function applyReferralInternal(referredUid: string, campusId: string, code: string): Promise<"applied" | "invalid"> {
  const referrerSnap = await db.collection(COL.users).where("referralCode", "==", code).limit(1).get();
  if (referrerSnap.empty) return "invalid";
  const referrerUid = referrerSnap.docs[0].id;
  if (referrerUid === referredUid) fail("self_referral", "You can't refer yourself.");
  const refRef = db.collection(COL.referrals).doc(referredUid);
  const applied = await db.runTransaction(async (tx) => {
    const existing = await tx.get(refRef);
    if (existing.exists) return false;
    const refMembership = await tx.get(db.collection(COL.memberships).doc(ids.membership(campusId, referrerUid)));
    const isAmbassador = refMembership.exists && (refMembership.get("roles") as string[]).includes("ambassador");
    tx.set(refRef, {
      referrerUid,
      referredUid,
      campusId,
      code,
      ambassador: isAmbassador,
      signupAt: serverTs(),
      firstAttendanceAt: null,
      rewardAwarded: false,
      signals: {},
    });
    tx.set(db.collection(COL.users).doc(referredUid), { referredBy: referrerUid }, { merge: true });
    return true;
  });
  if (!applied) fail("already_referred", "A referral is already linked to this account.");
  await track("referral_signup", { uid: referredUid, campusId, referrerUid });
  return "applied";
}

export const applyReferral = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId);
    const code = str(req.data?.code, "code", { max: 16 }).toUpperCase();
    // Only allow within 14 days of account creation to prevent retroactive gaming.
    const createdAt = actor.user?.createdAt?.toMillis?.() ?? Date.now();
    if (Date.now() - createdAt > 14 * 86400000) fail("referral_invalid", "Referral codes can only be applied within 14 days of joining.");
    const result = await applyReferralInternal(actor.uid, campusId, code);
    if (result === "invalid") fail("referral_invalid", "That referral code doesn't exist.");
    return { result };
  }),
);

/** Students request organizer/ambassador access; campus admin approves. Never self-elevating. */
export const requestRole = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const role = str(req.data?.role, "role") as Role;
    if (!(["organizer", "ambassador"] as Role[]).includes(role)) fail("invalid_argument", "You can only request organizer or ambassador access.");
    const note = str(req.data?.note, "note", { optional: true, max: 500 });
    const clubName = str(req.data?.clubName, "clubName", { optional: true, max: 120 });
    const m = await requireMembership(actor, campusId);
    if (m.roles.includes(role)) return { status: "already_granted" };
    const ref = db.collection(COL.memberships).doc(ids.membership(campusId, actor.uid));
    await ref.set(
      { requestedRoles: Array.from(new Set([...(m as unknown as { requestedRoles?: string[] }).requestedRoles ?? [], role])), roleRequests: { [role]: { note, clubName, requestedAt: serverTs(), status: "pending" } } },
      { merge: true },
    );
    return { status: "pending" };
  }),
);

/** Campus admin (or super admin) grants/revokes roles. Audited. */
export const setMembershipRole = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const targetUid = str(req.data?.uid, "uid");
    const role = str(req.data?.role, "role") as Role;
    const grant = req.data?.grant !== false;
    const reason = str(req.data?.reason, "reason", { optional: true, max: 500 });
    const clubId = str(req.data?.clubId, "clubId", { optional: true });
    const vendorId = str(req.data?.vendorId, "vendorId", { optional: true });
    const brandId = str(req.data?.brandId, "brandId", { optional: true });
    if (role === "super_admin") fail("permission_denied", "Super admin is managed at platform level.");
    if (role === "campus_admin") await requireSuperAdmin(actor);
    else await requireMembership(actor, campusId, ["campus_admin"]);
    if (targetUid === actor.uid && !(await isSuperAdmin(actor.uid))) fail("permission_denied", "You can't change your own roles.");

    const ref = db.collection(COL.memberships).doc(ids.membership(campusId, targetUid));
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const before = snap.exists ? { roles: snap.get("roles"), clubIds: snap.get("clubIds") } : null;
      const roles = new Set<string>(snap.exists ? snap.get("roles") ?? [] : ["student"]);
      const clubIds = new Set<string>(snap.exists ? snap.get("clubIds") ?? [] : []);
      if (grant) roles.add(role);
      else roles.delete(role);
      if (role === "organizer" && clubId) {
        if (grant) clubIds.add(clubId);
        else clubIds.delete(clubId);
      }
      const roleRequests = snap.get("roleRequests") ?? {};
      if (roleRequests[role]) roleRequests[role] = { ...roleRequests[role], status: grant ? "approved" : "rejected", decidedAt: serverTs(), decidedBy: actor.uid };
      const update: Record<string, unknown> = {
        campusId,
        uid: targetUid,
        roles: [...roles],
        clubIds: [...clubIds],
        status: snap.exists ? snap.get("status") : "active",
        roleRequests,
        requestedRoles: (snap.get("requestedRoles") ?? []).filter((r: string) => r !== role),
        updatedAt: serverTs(),
      };
      if (role === "vendor") update.vendorId = grant ? vendorId : null;
      if (role === "brand") update.brandId = grant ? brandId : null;
      if (role === "organizer" && grant) update.organizerApprovedAt = snap.get("organizerApprovedAt") ?? serverTs();
      tx.set(ref, update, { merge: true });
      if (role === "organizer" && clubId) {
        const clubRef = db.collection(COL.clubs).doc(clubId);
        tx.set(clubRef, { adminUids: grant ? FieldValue.arrayUnion(targetUid) : FieldValue.arrayRemove(targetUid) }, { merge: true });
      }
      writeAudit(
        { actorUid: actor.uid, action: grant ? "role.grant" : "role.revoke", entityType: "membership", entityId: ref.id, campusId, reason, before, after: { roles: [...roles], clubIds: [...clubIds] } },
        tx,
      );
    });
    return { ok: true };
  }),
);

/** Suspend / reactivate an account (campus admin). Requires reason; never destructive. */
export const setUserSuspension = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const targetUid = str(req.data?.uid, "uid");
    const suspend = req.data?.suspend === true;
    const reason = str(req.data?.reason, "reason", { max: 500 });
    await requireMembership(actor, campusId, ["campus_admin"]);
    if (targetUid === actor.uid) fail("permission_denied", "You can't suspend yourself.");
    const target = await db.collection(COL.memberships).doc(ids.membership(campusId, targetUid)).get();
    if (!target.exists) fail("not_found", "That user isn't a member of this campus.");
    await db.runTransaction(async (tx) => {
      const userRef = db.collection(COL.users).doc(targetUid);
      const before = (await tx.get(userRef)).get("status");
      tx.set(
        userRef,
        {
          status: suspend ? "suspended" : "active",
          suspension: suspend ? { reason, actorUid: actor.uid, at: serverTs(), campusId } : null,
        },
        { merge: true },
      );
      tx.update(target.ref, { status: suspend ? "suspended" : "active" });
      writeAudit({ actorUid: actor.uid, action: suspend ? "user.suspend" : "user.reactivate", entityType: "user", entityId: targetUid, campusId, reason, before: { status: before }, after: { status: suspend ? "suspended" : "active" } }, tx);
    });
    return { ok: true };
  }),
);

/** Switch the active campus context (must be a member). */
export const setActiveCampus = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId);
    await loadCampus(campusId);
    await db.collection(COL.users).doc(actor.uid).set({ activeCampusId: campusId }, { merge: true });
    return { ok: true };
  }),
);
