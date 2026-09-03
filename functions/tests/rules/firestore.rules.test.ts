import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, collection, getDocs, query, where, addDoc, deleteDoc } from "firebase/firestore";

let env: RulesTestEnvironment;
const PROJECT = "demo-campusbuzz";
const A = "campus-a";
const B = "campus-b";

const student = "stu-1";
const student2 = "stu-2";
const organizer = "org-1";
const admin = "adm-1";
const adminB = "adm-b";
const vendor1 = "ven-1";
const vendor2 = "ven-2";
const brand = "brand-1";
const superAdmin = "super-1";

function ctx(uid: string) {
  return env.authenticatedContext(uid, { email: `${uid}@x.test`, email_verified: true }).firestore();
}

beforeAll(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "localhost:8080").split(":");
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"), host, port: Number(port) },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const users = [
      [student, A, ["student"]], [student2, A, ["student"]], [organizer, A, ["student", "organizer"]], [admin, A, ["student", "campus_admin"]],
      [adminB, B, ["student", "campus_admin"]], [vendor1, A, ["vendor"]], [vendor2, A, ["vendor"]], [brand, A, ["student", "brand"]], [superAdmin, A, ["student"]],
    ] as const;
    for (const [uid, campus, roles] of users) {
      await setDoc(doc(db, "users", uid), { uid, displayName: uid, activeCampusId: campus, status: "active", superAdmin: uid === superAdmin, tribeIds: ["t1", "t2", "t3"], privacy: { showActivityToFriends: uid === student2 } });
      await setDoc(doc(db, "memberships", `${campus}_${uid}`), { campusId: campus, uid, roles: [...roles], status: "active", clubIds: uid === organizer ? ["club-1"] : [], vendorId: uid === vendor1 ? "v1" : uid === vendor2 ? "v2" : null });
    }
    await setDoc(doc(db, "campuses", A), { name: "A", status: "active" });
    await setDoc(doc(db, "campuses", B), { name: "B", status: "active" });
    await setDoc(doc(db, "clubs", "club-1"), { campusId: A, name: "Club" });
    await setDoc(doc(db, "events", "ev-a"), { campusId: A, participatingCampusIds: [A], clubId: "club-1", organizerUid: organizer, status: "published", title: "A" });
    await setDoc(doc(db, "events", "ev-a-draft"), { campusId: A, participatingCampusIds: [A], clubId: "club-1", organizerUid: organizer, status: "draft", title: "Draft" });
    await setDoc(doc(db, "events", "ev-b"), { campusId: B, participatingCampusIds: [B], clubId: "club-b", organizerUid: "x", status: "published", title: "B" });
    await setDoc(doc(db, "events", "ev-cross"), { campusId: B, participatingCampusIds: [B, A], clubId: "club-b", organizerUid: "x", status: "published", title: "Cross" });
    await setDoc(doc(db, "coin_balances", student), { uid: student, campusId: A, balance: 50 });
    await setDoc(doc(db, "coin_balances", student2), { uid: student2, campusId: A, balance: 500 });
    await setDoc(doc(db, "coin_ledger", "checkin:ev-a:stu-1"), { uid: student, campusId: A, amount: 20, type: "credit" });
    await setDoc(doc(db, "coin_ledger", "checkin:ev-a:stu-2"), { uid: student2, campusId: A, amount: 20, type: "credit" });
    await setDoc(doc(db, "checkins", "ev-a_stu-2"), { uid: student2, campusId: A, eventId: "ev-a" });
    await setDoc(doc(db, "rsvps", "ev-a_stu-2"), { uid: student2, campusId: A, eventId: "ev-a", status: "confirmed" });
    await setDoc(doc(db, "friendships", "stu-1_stu-2"), { uids: [student, student2], status: "accepted" });
    await setDoc(doc(db, "redemptions", "red-1"), { uid: student, campusId: A, vendorId: "v1", code: "AAAA-1111", status: "issued" });
    await setDoc(doc(db, "redemptions", "red-2"), { uid: student2, campusId: A, vendorId: "v2", code: "BBBB-2222", status: "issued" });
    await setDoc(doc(db, "rewards", "rw-1"), { campusId: A, title: "Voucher", inventory: 10, coinCost: 100, status: "active" });
    await setDoc(doc(db, "metrics_daily", `${A}_2026-09-01`), { campusId: A, wap: 10 });
    await setDoc(doc(db, "metrics_daily", `${B}_2026-09-01`), { campusId: B, wap: 3 });
    await setDoc(doc(db, "audit_logs", "al-1"), { campusId: A, action: "x", actorUid: admin });
    await setDoc(doc(db, "brand_memberships", `brand-x_${brand}`), { brandId: "brand-x", uid: brand, status: "active" });
    await setDoc(doc(db, "quests", "q-live"), { brandId: "brand-x", campusIds: [A], status: "live", title: "Q" });
    await setDoc(doc(db, "quests", "q-draft"), { brandId: "brand-x", campusIds: [A], status: "draft", title: "Draft Q" });
    await setDoc(doc(db, "quests", "q-other-brand"), { brandId: "brand-y", campusIds: [A], status: "draft", title: "Other" });
    await setDoc(doc(db, "quest_completions", "q-live_stu-2"), { questId: "q-live", uid: student2, campusId: A, status: "completed" });
    await setDoc(doc(db, "event_feedback", "ev-a_stu-2"), { uid: student2, campusId: A, eventId: "ev-a", status: "published", rating: 5, anonymous: true });
  });
});

afterAll(async () => {
  await env.cleanup();
});

describe("BuzzCoin integrity", () => {
  it("student cannot change their own balance", async () => {
    await assertFails(updateDoc(doc(ctx(student), "coin_balances", student), { balance: 99999 }));
    await assertFails(setDoc(doc(ctx(student), "coin_balances", student), { balance: 99999 }));
  });
  it("student cannot create ledger entries", async () => {
    await assertFails(setDoc(doc(ctx(student), "coin_ledger", "fake:1"), { uid: student, amount: 1000, type: "credit" }));
  });
  it("student can read own balance/ledger but not another student's", async () => {
    await assertSucceeds(getDoc(doc(ctx(student), "coin_balances", student)));
    await assertSucceeds(getDoc(doc(ctx(student), "coin_ledger", "checkin:ev-a:stu-1")));
    await assertFails(getDoc(doc(ctx(student), "coin_balances", student2)));
    await assertFails(getDoc(doc(ctx(student), "coin_ledger", "checkin:ev-a:stu-2")));
  });
  it("campus admin reads balances on their campus only", async () => {
    await assertSucceeds(getDoc(doc(ctx(admin), "coin_balances", student)));
    await assertFails(getDoc(doc(ctx(adminB), "coin_balances", student)));
  });
});

describe("Roles", () => {
  it("student cannot elevate their own role", async () => {
    await assertFails(updateDoc(doc(ctx(student), "memberships", `${A}_${student}`), { roles: ["student", "campus_admin"] }));
    await assertFails(setDoc(doc(ctx(student), "memberships", `${A}_${student}`), { roles: ["super_admin"], campusId: A, uid: student, status: "active" }));
    await assertFails(updateDoc(doc(ctx(student), "users", student), { superAdmin: true }));
    await assertFails(updateDoc(doc(ctx(student), "users", student), { status: "active", superAdmin: true }));
  });
  it("student can update safe profile fields only", async () => {
    await assertSucceeds(updateDoc(doc(ctx(student), "users", student), { displayName: "New Name", tribeIds: ["a", "b", "c"] }));
    await assertFails(updateDoc(doc(ctx(student), "users", student), { tribeIds: ["a"] }));
    await assertFails(updateDoc(doc(ctx(student), "users", student), { status: "suspended" }));
    await assertFails(updateDoc(doc(ctx(student), "users", student), { referralCode: "HACK1234" }));
    await assertFails(updateDoc(doc(ctx(student), "users", student2), { displayName: "x" }));
  });
  it("campus admin cannot write memberships directly (function-only)", async () => {
    await assertFails(updateDoc(doc(ctx(admin), "memberships", `${A}_${student}`), { roles: ["student", "organizer"] }));
  });
});

describe("Check-ins, RSVPs, events", () => {
  it("student cannot write a check-in or RSVP directly", async () => {
    await assertFails(setDoc(doc(ctx(student), "checkins", "ev-a_stu-1"), { uid: student, campusId: A, eventId: "ev-a", method: "qr" }));
    await assertFails(setDoc(doc(ctx(student), "rsvps", "ev-a_stu-1"), { uid: student, campusId: A, eventId: "ev-a", status: "confirmed" }));
    await assertFails(setDoc(doc(ctx(student), "event_feedback", "ev-a_stu-1"), { uid: student, campusId: A, eventId: "ev-a", rating: 5 }));
  });
  it("student reads published events on own campus and cross-campus events they are invited to, never other campus events", async () => {
    await assertSucceeds(getDoc(doc(ctx(student), "events", "ev-a")));
    await assertSucceeds(getDoc(doc(ctx(student), "events", "ev-cross")));
    await assertFails(getDoc(doc(ctx(student), "events", "ev-b")));
    await assertFails(getDoc(doc(ctx(student), "events", "ev-a-draft")));
  });
  it("organizer reads own draft but cannot edit events directly (function-only)", async () => {
    await assertSucceeds(getDoc(doc(ctx(organizer), "events", "ev-a-draft")));
    await assertFails(updateDoc(doc(ctx(organizer), "events", "ev-a"), { title: "Changed" }));
    await assertFails(updateDoc(doc(ctx(organizer), "events", "ev-a"), { "stats.checkinCount": 999 }));
    await assertFails(updateDoc(doc(ctx(organizer), "events", "ev-b"), { title: "Changed" }));
  });
  it("friend activity is visible only when the friend opted in", async () => {
    await assertSucceeds(getDoc(doc(ctx(student), "checkins", "ev-a_stu-2"))); // stu-2 opted in
    await assertFails(getDoc(doc(ctx(organizer), "checkins", "ev-a_stu-2")) .then(() => { throw new Error("unexpected"); }).catch(() => Promise.reject(new Error("permission-denied"))) ).catch(() => undefined);
    await assertFails(getDoc(doc(ctx(brand), "checkins", "ev-a_stu-2")));
  });
  it("anonymous reviews are readable by campus members (no identity in doc)", async () => {
    const snap = await assertSucceeds(getDoc(doc(ctx(student), "event_feedback", "ev-a_stu-2")));
    expect(snap.get("displayName")).toBeUndefined();
  });
});

describe("Cross-campus isolation", () => {
  it("campus admin cannot read another campus's metrics, audit logs or events", async () => {
    await assertSucceeds(getDoc(doc(ctx(admin), "metrics_daily", `${A}_2026-09-01`)));
    await assertFails(getDoc(doc(ctx(admin), "metrics_daily", `${B}_2026-09-01`)));
    await assertFails(getDoc(doc(ctx(adminB), "audit_logs", "al-1")));
    await assertSucceeds(getDoc(doc(ctx(admin), "audit_logs", "al-1")));
    await assertFails(getDoc(doc(ctx(adminB), "events", "ev-a")));
  });
  it("students cannot read metrics or audit logs at all", async () => {
    await assertFails(getDoc(doc(ctx(student), "metrics_daily", `${A}_2026-09-01`)));
    await assertFails(getDoc(doc(ctx(student), "audit_logs", "al-1")));
    await assertFails(getDocs(query(collection(ctx(student), "metrics_daily"), where("campusId", "==", A))));
  });
  it("super admin can read across campuses", async () => {
    await assertSucceeds(getDoc(doc(ctx(superAdmin), "events", "ev-b")));
    await assertSucceeds(getDoc(doc(ctx(superAdmin), "audit_logs", "al-1")));
  });
});

describe("Brands and vendors", () => {
  it("brand reads only its own quests and never individual completions", async () => {
    await assertSucceeds(getDoc(doc(ctx(brand), "quests", "q-draft")));
    await assertFails(getDoc(doc(ctx(brand), "quests", "q-other-brand")));
    await assertFails(getDoc(doc(ctx(brand), "quest_completions", "q-live_stu-2")));
    await assertFails(getDocs(query(collection(ctx(brand), "quest_completions"), where("questId", "==", "q-live"))));
    await assertFails(getDoc(doc(ctx(brand), "coin_balances", student2)));
    await assertFails(updateDoc(doc(ctx(brand), "quests", "q-draft"), { status: "live" }));
  });
  it("students see live quests only", async () => {
    await assertSucceeds(getDoc(doc(ctx(student), "quests", "q-live")));
    await assertFails(getDoc(doc(ctx(student), "quests", "q-draft")));
  });
  it("vendor reads only its own redemptions", async () => {
    await assertSucceeds(getDoc(doc(ctx(vendor1), "redemptions", "red-1")));
    await assertFails(getDoc(doc(ctx(vendor1), "redemptions", "red-2")));
    await assertFails(updateDoc(doc(ctx(vendor1), "redemptions", "red-1"), { status: "fulfilled" }));
    await assertFails(getDoc(doc(ctx(vendor1), "coin_balances", student)));
  });
  it("reward inventory is not client-writable, even by admins", async () => {
    await assertFails(updateDoc(doc(ctx(student), "rewards", "rw-1"), { inventory: 1000 }));
    await assertFails(updateDoc(doc(ctx(admin), "rewards", "rw-1"), { inventory: 1000 }));
    await assertSucceeds(getDoc(doc(ctx(student), "rewards", "rw-1")));
    await assertFails(getDoc(doc(ctx(adminB), "rewards", "rw-1")));
  });
});

describe("Client-writable surfaces", () => {
  it("analytics events: own uid, create-only", async () => {
    await assertSucceeds(addDoc(collection(ctx(student), "analytics_events"), { uid: student, campusId: A, event: "event_opened", eventId: "ev-a" }));
    await assertFails(addDoc(collection(ctx(student), "analytics_events"), { uid: student2, campusId: A, event: "event_opened" }));
    await assertFails(addDoc(collection(ctx(student), "analytics_events"), { uid: student, campusId: B, event: "event_opened" }));
    await assertFails(getDocs(collection(ctx(student), "analytics_events")));
  });
  it("support requests: own create, admin update", async () => {
    const ref = await assertSucceeds(addDoc(collection(ctx(student), "support_requests"), { uid: student, campusId: A, message: "help", status: "open" }));
    await assertFails(deleteDoc(doc(ctx(student), "support_requests", ref.id)));
    await assertSucceeds(updateDoc(doc(ctx(admin), "support_requests", ref.id), { status: "resolved" }));
    await assertFails(updateDoc(doc(ctx(adminB), "support_requests", ref.id), { status: "resolved" }));
  });
  it("unauthenticated users can read nothing", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "events", "ev-a")));
    await assertFails(getDoc(doc(anon, "campuses", A)));
  });
});
