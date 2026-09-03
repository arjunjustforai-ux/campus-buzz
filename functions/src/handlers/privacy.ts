import { getAuth } from "firebase-admin/auth";
import { getStorage } from "firebase-admin/storage";
import { onCall } from "firebase-functions/v2/https";
import { COL } from "../config/collections";
import { fail } from "../domain/errors";
import { writeAudit } from "../lib/audit";
import { callableHandler, requireAuth, str } from "../lib/auth";
import { db, forEachPage, inc, serverTs } from "../lib/firestore";
import { callableOpts } from "../lib/options";

const USER_COLLECTIONS: Array<{ col: string; field: string }> = [
  { col: COL.rsvps, field: "uid" },
  { col: COL.checkins, field: "uid" },
  { col: COL.eventFeedback, field: "uid" },
  { col: COL.coinLedger, field: "uid" },
  { col: COL.redemptions, field: "uid" },
  { col: COL.questCompletions, field: "uid" },
  { col: COL.surveyResponses, field: "uid" },
  { col: COL.memberships, field: "uid" },
  { col: COL.notificationDeliveryLogs, field: "uid" },
];

/** Export everything we hold about the caller as JSON (stored to a private Storage path + returned inline). */
export const exportMyData = onCall(
  { ...callableOpts, timeoutSeconds: 300, memory: "1GiB" },
  callableHandler(async (req) => {
    const actor = await requireAuth(req, { allowUnverified: true });
    const out: Record<string, unknown> = { exportedAt: new Date().toISOString(), uid: actor.uid };
    const user = await db.collection(COL.users).doc(actor.uid).get();
    out.profile = user.exists ? scrub(user.data()!) : null;
    const [balance, stats, referral] = await Promise.all([db.collection(COL.coinBalances).doc(actor.uid).get(), db.collection(COL.participationStats).doc(actor.uid).get(), db.collection(COL.referrals).doc(actor.uid).get()]);
    out.coinBalance = balance.data() ?? null; out.participationStats = stats.data() ?? null; out.referral = referral.data() ?? null;
    for (const { col, field } of USER_COLLECTIONS) {
      const rows: unknown[] = [];
      await forEachPage(db.collection(col).where(field, "==", actor.uid), 500, async (docs) => { for (const d of docs) rows.push({ id: d.id, ...scrub(d.data()) }); });
      out[col] = rows;
    }
    const friends: unknown[] = [];
    await forEachPage(db.collection(COL.friendships).where("uids", "array-contains", actor.uid), 500, async (docs) => { for (const d of docs) friends.push({ id: d.id, ...scrub(d.data()) }); });
    out.friendships = friends;
    const json = JSON.stringify(out, null, 2);
    let downloadPath: string | null = null;
    try {
      const file = getStorage().bucket().file(`exports/${actor.uid}/campusbuzz-export-${Date.now()}.json`);
      await file.save(json, { contentType: "application/json" });
      downloadPath = file.name;
    } catch (e) {
      console.warn("export upload skipped", e);
    }
    await db.collection(COL.dataExports).add({ uid: actor.uid, path: downloadPath, bytes: json.length, at: serverTs() });
    writeAudit({ actorUid: actor.uid, action: "privacy.export", entityType: "user", entityId: actor.uid, after: { bytes: json.length } });
    return { json, storagePath: downloadPath };
  }),
);

/**
 * Account deletion: removes PII, anonymizes participation records (aggregate
 * metrics stay valid), revokes auth. Audit rows keep the uid only. Completes
 * immediately — well inside the 7-business-day target.
 */
export const deleteMyAccount = onCall(
  { ...callableOpts, timeoutSeconds: 300 },
  callableHandler(async (req) => {
    const actor = await requireAuth(req, { allowUnverified: true });
    const confirm = str(req.data?.confirm, "confirm", { optional: true });
    if (confirm !== "DELETE") fail("invalid_argument", "Type DELETE to confirm.");
    const uid = actor.uid;
    const anonName = "Deleted student";
    // 1) Profile → tombstone (keeps uid so ledger integrity checks still sum correctly).
    await db.collection(COL.users).doc(uid).set({ uid, email: null, displayName: anonName, avatarUrl: null, tribeIds: [], primaryTribeId: null, fcmTokens: [], notificationPrefs: { transactional: false, reminders: false, engagement: false, postEvent: false }, privacy: { showActivityToFriends: false, talentProfileOptIn: false }, status: "deleted", referralCode: null, deletedAt: serverTs() }, { merge: false });
    // 2) Memberships → removed (they hold displayName).
    await forEachPage(db.collection(COL.memberships).where("uid", "==", uid), 200, async (docs) => { const b = db.batch(); docs.forEach((d) => b.delete(d.ref)); await b.commit(); });
    // 3) Reviews → anonymized, friendships → deleted, pending notifications → cancelled.
    await forEachPage(db.collection(COL.eventFeedback).where("uid", "==", uid), 200, async (docs) => { const b = db.batch(); docs.forEach((d) => b.update(d.ref, { anonymous: true, displayName: null })); await b.commit(); });
    await forEachPage(db.collection(COL.friendships).where("uids", "array-contains", uid), 200, async (docs) => { const b = db.batch(); docs.forEach((d) => b.delete(d.ref)); await b.commit(); });
    await forEachPage(db.collection(COL.notificationJobs).where("uid", "==", uid).where("status", "==", "pending"), 200, async (docs) => { const b = db.batch(); docs.forEach((d) => b.update(d.ref, { status: "cancelled" })); await b.commit(); });
    // 4) Cancel future RSVPs so organizer counts stay honest.
    await forEachPage(db.collection(COL.rsvps).where("uid", "==", uid).where("status", "in", ["confirmed", "waitlisted"]), 100, async (docs) => {
      for (const d of docs) {
        const wasConfirmed = d.get("status") === "confirmed";
        await db.runTransaction(async (tx) => { tx.update(d.ref, { status: "cancelled", cancelledAt: serverTs() }); tx.update(db.collection(COL.events).doc(d.get("eventId")), { [wasConfirmed ? "stats.rsvpCount" : "stats.waitlistCount"]: inc(-1) }); });
      }
    });
    // 5) Storage: avatar.
    try { await getStorage().bucket().deleteFiles({ prefix: `avatars/${uid}/` }); } catch (e) { console.warn("avatar delete skipped", e); }
    // 6) Auth user.
    try { await getAuth().deleteUser(uid); } catch (e) { console.warn("auth delete skipped", e); }
    writeAudit({ actorUid: uid, action: "privacy.delete", entityType: "user", entityId: uid, after: { status: "deleted" } });
    return { ok: true };
  }),
);

function scrub(d: FirebaseFirestore.DocumentData): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(d)) {
    if (v && typeof v === "object" && "toMillis" in v && typeof (v as { toMillis: unknown }).toMillis === "function") out[k] = new Date((v as { toMillis: () => number }).toMillis()).toISOString();
    else out[k] = v;
  }
  return out;
}
