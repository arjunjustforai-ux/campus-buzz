import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { fail } from "../domain/errors";
import { track } from "../lib/analytics";
import { callableHandler, requireAuth, requireMembership, str } from "../lib/auth";
import { requireFlag } from "../lib/campus";
import { db, serverTs } from "../lib/firestore";
import { enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

/** Lightweight friend graph: request / accept / decline / unfriend / block. No chat. */
export const sendFriendRequest = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const targetUid = str(req.data?.uid, "uid");
    const campusId = actor.user?.activeCampusId as string;
    await requireMembership(actor, campusId);
    await requireFlag(campusId, "friends_enabled");
    if (targetUid === actor.uid) fail("invalid_argument", "That's you.");
    const target = await db.collection(COL.memberships).doc(ids.membership(campusId, targetUid)).get();
    if (!target.exists || target.get("status") !== "active") fail("not_found", "That student isn't on your campus.");
    const ref = db.collection(COL.friendships).doc(ids.friendship(actor.uid, targetUid));
    const created = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) {
        const s = snap.get("status");
        if (s === "blocked") fail("permission_denied", "You can't send a request to this student.");
        if (s === "accepted") return false;
        if (s === "pending" && snap.get("requesterUid") !== actor.uid) {
          tx.update(ref, { status: "accepted", respondedAt: serverTs() });
          return true;
        }
        return false;
      }
      tx.set(ref, { uids: [actor.uid, targetUid].sort(), requesterUid: actor.uid, campusId, status: "pending", createdAt: serverTs(), respondedAt: null, blockedBy: null });
      return true;
    });
    if (created) {
      await track("friend_request_sent", { uid: actor.uid, campusId });
      await enqueueNotification({ uid: targetUid, campusId, category: "engagement", title: `${actor.user?.displayName ?? "Someone"} wants to be friends`, body: "Accept to see each other's event plans.", route: "/friends", dedupeKey: `friend:${ref.id}:req` });
    }
    return { ok: true };
  }),
);

export const respondFriendRequest = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const otherUid = str(req.data?.uid, "uid");
    const accept = req.data?.accept === true;
    const ref = db.collection(COL.friendships).doc(ids.friendship(actor.uid, otherUid));
    const snap = await ref.get();
    if (!snap.exists || snap.get("status") !== "pending" || snap.get("requesterUid") === actor.uid) fail("not_found", "No pending request from this student.");
    if (accept) {
      await ref.update({ status: "accepted", respondedAt: serverTs() });
      await track("friend_request_accepted", { uid: actor.uid, campusId: snap.get("campusId") });
    } else {
      await ref.delete();
    }
    return { ok: true };
  }),
);

export const removeFriend = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const otherUid = str(req.data?.uid, "uid");
    const block = req.data?.block === true;
    const ref = db.collection(COL.friendships).doc(ids.friendship(actor.uid, otherUid));
    if (block) {
      await ref.set({ uids: [actor.uid, otherUid].sort(), requesterUid: actor.uid, campusId: actor.user?.activeCampusId ?? null, status: "blocked", blockedBy: actor.uid, createdAt: serverTs(), respondedAt: serverTs() });
    } else {
      const snap = await ref.get();
      if (snap.exists && snap.get("status") === "blocked" && snap.get("blockedBy") !== actor.uid) fail("permission_denied");
      await ref.delete();
    }
    return { ok: true };
  }),
);
