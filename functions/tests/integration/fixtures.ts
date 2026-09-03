/**
 * Minimal fixtures for callable integration tests against the Firestore emulator.
 * Each test file uses a unique campus id so suites don't interfere.
 */
import type { CallableRequest } from "firebase-functions/v2/https";
import { COL, ids } from "../../src/config/collections";
import { DEFAULT_ECONOMY, DEFAULT_FEATURE_FLAGS, DEFAULT_PILOT } from "../../src/config/defaults";
import type { EconomyConfig, Role } from "../../src/domain/types";
import { db, Timestamp } from "../../src/lib/firestore";

process.env.FUNCTIONS_EMULATOR = "true";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-campusbuzz";

export const TZ = "Asia/Kolkata";

export function asUser(uid: string, email = `${uid}@test.campusbuzz.test`, data: unknown = {}): CallableRequest<any> {
  return { data, auth: { uid, token: { email, email_verified: true } as any }, rawRequest: {} as any, acceptsStreaming: false } as CallableRequest<any>;
}

export async function makeCampus(campusId: string, economy: Partial<EconomyConfig> = {}) {
  await db.collection(COL.campuses).doc(campusId).set({ name: campusId, shortName: campusId, domains: [`${campusId}.test`], timezone: TZ, status: "active", economy: { ...DEFAULT_ECONOMY, ...economy }, pilot: DEFAULT_PILOT, featureFlags: { ...DEFAULT_FEATURE_FLAGS, intercampus_events_enabled: true }, createdAt: Timestamp.now() });
  for (const t of ["t-finance", "t-coders", "t-sports"]) await db.collection(COL.tribes).doc(`${campusId}-${t}`).set({ campusId, name: t, active: true, order: 0 });
  await db.collection(COL.clubs).doc(`${campusId}-club`).set({ campusId, name: "Test Club", status: "active", adminUids: [], stats: { events: 0 } });
  return { campusId, clubId: `${campusId}-club`, tribeIds: ["t-finance", "t-coders", "t-sports"].map((t) => `${campusId}-${t}`) };
}

export async function makeUser(campusId: string, uid: string, roles: Role[] = ["student"], extra: Record<string, unknown> = {}) {
  const tribeIds = ["t-finance", "t-coders", "t-sports"].map((t) => `${campusId}-${t}`);
  await db.collection(COL.users).doc(uid).set({ uid, email: `${uid}@${campusId}.test`, displayName: uid, activeCampusId: campusId, campusIds: [campusId], tribeIds, primaryTribeId: tribeIds[0], onboardingCompleted: true, status: "active", referralCode: `R${uid.replace(/[^a-z0-9]/gi, "").slice(-9).toUpperCase()}`, notificationPrefs: { transactional: true, reminders: true, engagement: true, postEvent: true }, privacy: { showActivityToFriends: false }, createdAt: Timestamp.now(), superAdmin: false, ...extra });
  await db.collection(COL.memberships).doc(ids.membership(campusId, uid)).set({ campusId, uid, roles, status: "active", clubIds: roles.includes("organizer") ? [`${campusId}-club`] : [], requestedRoles: [], joinedAt: Timestamp.now(), displayName: uid, tribeIds, ...(extra.vendorId ? { vendorId: extra.vendorId } : {}) });
  await db.collection(COL.participationStats).doc(uid).set({ uid, campusId, streak: 0, lastWeekKey: null, multiplierActive: false, totalCheckins: 0, totalRsvps: 0, attendedTags: {}, attendedWeekdays: {}, attendedHourBuckets: {} });
  await db.collection(COL.coinBalances).doc(uid).set({ uid, campusId, balance: 0, lifetimeEarned: 0, lifetimeRedeemed: 0, lifetimeExpired: 0 });
  return uid;
}

export async function makeEvent(campusId: string, eventId: string, opts: { startInMinutes?: number; durationMinutes?: number; capacity?: number; waitlist?: boolean; organizerUid?: string; status?: string; participating?: string[] } = {}) {
  const start = new Date(Date.now() + (opts.startInMinutes ?? 10) * 60000);
  const end = new Date(start.getTime() + (opts.durationMinutes ?? 120) * 60000);
  await db.collection(COL.events).doc(eventId).set({
    campusId, hostCampusId: campusId, participatingCampusIds: opts.participating ?? [campusId], clubId: `${campusId}-club`, clubName: "Test Club", organizerUid: opts.organizerUid ?? `${campusId}-org`,
    title: `Event ${eventId}`, description: "desc", posterUrl: null, startAt: Timestamp.fromDate(start), endAt: Timestamp.fromDate(end), location: { name: "Hall", address: "", lat: null, lng: null },
    capacity: opts.capacity ?? 100, waitlistEnabled: opts.waitlist ?? false, tribeIds: [`${campusId}-t-finance`], tags: ["test"], contact: "", registrationClosesAt: null, certificateEnabled: true,
    checkinOpensAt: Timestamp.fromMillis(start.getTime() - 30 * 60000), checkinClosesAt: Timestamp.fromMillis(end.getTime() + 120 * 60000), checkinActive: false,
    status: opts.status ?? "published", publishedAt: Timestamp.now(), reviewStatus: "approved", stats: { rsvpCount: 0, waitlistCount: 0, checkinCount: 0, manualCheckinCount: 0, feedbackCount: 0, ratingSum: 0, ratingAvg: 0, opens: 0, impressions: 0 }, tribeCheckins: {}, tribeRsvps: {}, organizerBonusAwarded: false, searchTokens: [], createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  return eventId;
}

export async function balance(uid: string): Promise<number> {
  const s = await db.collection(COL.coinBalances).doc(uid).get();
  return Number(s.get("balance") ?? 0);
}

export async function ledgerSum(uid: string): Promise<number> {
  const s = await db.collection(COL.coinLedger).where("uid", "==", uid).get();
  return s.docs.reduce((a, d) => a + Number(d.get("amount")), 0);
}

export async function expectDomainError(p: Promise<unknown>, code: string): Promise<void> {
  try {
    await p;
  } catch (e: any) {
    const c = e?.details?.code ?? e?.code;
    if (c !== code) throw new Error(`expected domain error ${code}, got ${c}: ${e?.message}`);
    return;
  }
  throw new Error(`expected domain error ${code}, but call succeeded`);
}
