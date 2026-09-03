import { beforeAll, describe, expect, it } from "vitest";
import { COL, ids } from "../../src/config/collections";
import { db, Timestamp } from "../../src/lib/firestore";
import { asUser, balance, expectDomainError, ledgerSum, makeCampus, makeEvent, makeUser } from "./fixtures";
import { adminAdjustCoins, fulfillRedemption, redeemReward, refundRedemption, upsertReward, validateRedemption } from "../../src/handlers/rewards";
import { applyFifoConsumption, expireCoinsOnce } from "../../src/handlers/scheduled";
import { approveBrandQuest, joinQuest, saveQuestDraft, submitBrandQuest, getBrandQuestAnalytics } from "../../src/handlers/quests";
import { checkInWithQr, issueEventQrToken, startEventCheckin } from "../../src/handlers/checkin";
import { setMembershipRole, setUserSuspension } from "../../src/handlers/auth";
import { createRsvp } from "../../src/handlers/rsvp";

const C = "campus-econ";
const admin = `${C}-admin`;
const vendorUser = `${C}-vendor`;

async function seedBalance(uid: string, amount: number, key = `seed:${uid}:${amount}:${Math.random()}`) {
  await db.collection(COL.coinLedger).doc(key).set({ key, uid, campusId: C, type: "credit", reason: "admin_adjustment", amount, remaining: amount, refId: null, meta: {}, economyVersion: 1, expiresAt: Timestamp.fromMillis(Date.now() + 90 * 86400000), expired: false, createdAt: Timestamp.now() });
  await db.collection(COL.coinBalances).doc(uid).set({ uid, campusId: C, balance: (await balance(uid)) + amount }, { merge: true });
  return key;
}

describe("Rewards & redemption", () => {
  let rewardId: string;
  beforeAll(async () => {
    await makeCampus(C);
    await makeUser(C, admin, ["student", "campus_admin"]);
    await makeUser(C, vendorUser, ["vendor"], { vendorId: "v1" });
    await makeUser(C, `${C}-othervendor`, ["vendor"], { vendorId: "v2" });
    for (const u of ["r1", "r2", "r3", "r4"]) await makeUser(C, `${C}-${u}`);
    await db.collection(COL.vendors).doc("v1").set({ campusId: C, name: "Canteen", status: "active", stats: { fulfilled: 0, pendingSettlementValue: 0 } });
    const r = (await upsertReward.run(asUser(admin, undefined, { campusId: C, title: "₹50 voucher", type: "voucher", coinCost: 100, inventory: 1, faceValue: 50, vendorId: "v1", perUserLimit: 1 }))) as any;
    rewardId = r.rewardId;
  });

  it("students cannot create rewards; admin creation is audited", async () => {
    await expectDomainError(upsertReward.run(asUser(`${C}-r1`, undefined, { campusId: C, title: "x", type: "voucher", coinCost: 1, inventory: 1 })), "permission_denied");
    const audit = await db.collection(COL.auditLogs).where("action", "==", "reward.create").where("entityId", "==", rewardId).get();
    expect(audit.size).toBe(1);
  });

  it("insufficient coins is rejected with the shortfall", async () => {
    await seedBalance(`${C}-r1`, 75);
    try {
      await redeemReward.run(asUser(`${C}-r1`, undefined, { rewardId }));
      throw new Error("should fail");
    } catch (e: any) {
      expect(e.details.code).toBe("insufficient_coins");
      expect(e.details.shortfall).toBe(25);
    }
    expect(await balance(`${C}-r1`)).toBe(75);
  });

  it("simultaneous redemptions never over-sell inventory or double-spend", async () => {
    await seedBalance(`${C}-r2`, 200);
    await seedBalance(`${C}-r3`, 200);
    await seedBalance(`${C}-r4`, 200);
    const results = await Promise.allSettled([
      redeemReward.run(asUser(`${C}-r2`, undefined, { rewardId })),
      redeemReward.run(asUser(`${C}-r3`, undefined, { rewardId })),
      redeemReward.run(asUser(`${C}-r4`, undefined, { rewardId })),
    ]);
    const ok = results.filter((r) => r.status === "fulfilled");
    expect(ok).toHaveLength(1);
    const failed = results.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
    expect(failed.every((f) => f.reason?.details?.code === "reward_out_of_stock")).toBe(true);
    const reward = await db.collection(COL.rewards).doc(rewardId).get();
    expect(reward.get("inventory")).toBe(0);
    expect(reward.get("stats.redeemed")).toBe(1);
    const totalBalance = (await balance(`${C}-r2`)) + (await balance(`${C}-r3`)) + (await balance(`${C}-r4`));
    expect(totalBalance).toBe(500);
    for (const u of ["r2", "r3", "r4"]) expect(await ledgerSum(`${C}-${u}`)).toBe(await balance(`${C}-${u}`));
  });

  it("vendor validates + fulfils a code; other vendors and re-fulfilment are refused", async () => {
    const red = await db.collection(COL.redemptions).where("rewardId", "==", rewardId).limit(1).get();
    const code = red.docs[0].get("code");
    const v = (await validateRedemption.run(asUser(vendorUser, undefined, { code }))) as any;
    expect(v.valid).toBe(true);
    await expectDomainError(validateRedemption.run(asUser(`${C}-othervendor`, undefined, { code })), "permission_denied");
    await expectDomainError(validateRedemption.run(asUser(`${C}-r1`, undefined, { code })), "permission_denied");
    expect((await fulfillRedemption.run(asUser(vendorUser, undefined, { code }))) as any).toEqual({ status: "fulfilled" });
    expect((await fulfillRedemption.run(asUser(vendorUser, undefined, { code }))) as any).toEqual({ status: "already" });
    const after = await red.docs[0].ref.get();
    expect(after.get("status")).toBe("fulfilled");
    expect(after.get("settlementMonth")).toMatch(/^\d{4}-\d{2}$/);
    await expectDomainError(validateRedemption.run(asUser(vendorUser, undefined, { code: "NOPE-0000" })), "redemption_invalid");
    // Fulfilled redemptions cannot be refunded.
    await expectDomainError(refundRedemption.run(asUser(admin, undefined, { redemptionId: red.docs[0].id, reason: "x" })), "redemption_invalid");
  });

  it("refund credits coins back exactly once and restores inventory", async () => {
    const r = (await upsertReward.run(asUser(admin, undefined, { campusId: C, title: "Print", type: "printing_credit", coinCost: 50, inventory: 5 }))) as any;
    await seedBalance(`${C}-r1`, 100);
    const before = await balance(`${C}-r1`);
    const red = (await redeemReward.run(asUser(`${C}-r1`, undefined, { rewardId: r.rewardId }))) as any;
    expect(await balance(`${C}-r1`)).toBe(before - 50);
    await refundRedemption.run(asUser(admin, undefined, { redemptionId: red.redemptionId, reason: "vendor closed" }));
    await refundRedemption.run(asUser(admin, undefined, { redemptionId: red.redemptionId, reason: "vendor closed" }));
    expect(await balance(`${C}-r1`)).toBe(before);
    expect((await db.collection(COL.rewards).doc(r.rewardId).get()).get("inventory")).toBe(5);
  });

  it("admin adjustments require a reason and write ledger + audit; students cannot adjust", async () => {
    await expectDomainError(adminAdjustCoins.run(asUser(`${C}-r1`, undefined, { campusId: C, uid: `${C}-r1`, amount: 1000, reason: "gimme" })), "permission_denied");
    await expectDomainError(adminAdjustCoins.run(asUser(admin, undefined, { campusId: C, uid: `${C}-r1`, amount: 10 })), "invalid_argument");
    const b = await balance(`${C}-r1`);
    await adminAdjustCoins.run(asUser(admin, undefined, { campusId: C, uid: `${C}-r1`, amount: -10, reason: "duplicate manual check-in" }));
    expect(await balance(`${C}-r1`)).toBe(b - 10);
    expect(await ledgerSum(`${C}-r1`)).toBe(b - 10);
    const audit = await db.collection(COL.auditLogs).where("action", "==", "coins.adjust").where("entityId", "==", `${C}-r1`).get();
    expect(audit.size).toBe(1);
    await expectDomainError(adminAdjustCoins.run(asUser(admin, undefined, { campusId: C, uid: `${C}-r1`, amount: -100000, reason: "x" })), "insufficient_coins");
  });
});

describe("Coin expiry (ledger-based, FIFO)", () => {
  const u = `${C}-exp`;
  beforeAll(async () => {
    await makeCampus(C);
    await makeUser(C, u);
  });

  it("expires only the unspent remainder of old credits", async () => {
    const old = `credit:old:${u}`;
    const fresh = `credit:fresh:${u}`;
    await db.collection(COL.coinLedger).doc(old).set({ key: old, uid: u, campusId: C, type: "credit", reason: "checkin", amount: 20, remaining: 20, economyVersion: 1, expiresAt: Timestamp.fromMillis(Date.now() - 1000), expired: false, createdAt: Timestamp.fromMillis(Date.now() - 91 * 86400000), meta: {} });
    await db.collection(COL.coinLedger).doc(fresh).set({ key: fresh, uid: u, campusId: C, type: "credit", reason: "checkin", amount: 20, remaining: 20, economyVersion: 1, expiresAt: Timestamp.fromMillis(Date.now() + 80 * 86400000), expired: false, createdAt: Timestamp.now(), meta: {} });
    await db.collection(COL.coinLedger).doc(`debit:${u}`).set({ key: `debit:${u}`, uid: u, campusId: C, type: "debit", reason: "redemption", amount: -15, economyVersion: 1, fifoApplied: false, createdAt: Timestamp.now(), meta: {} });
    await db.collection(COL.coinBalances).doc(u).set({ uid: u, campusId: C, balance: 25 }, { merge: true });
    await applyFifoConsumption();
    expect((await db.collection(COL.coinLedger).doc(old).get()).get("remaining")).toBe(5);
    expect((await db.collection(COL.coinLedger).doc(fresh).get()).get("remaining")).toBe(20);
    const r = await expireCoinsOnce();
    expect(r.coins).toBeGreaterThanOrEqual(5);
    expect(await balance(u)).toBe(20);
    expect(await ledgerSum(u)).toBe(20);
    const again = await expireCoinsOnce();
    expect(await balance(u)).toBe(20); // idempotent
    expect(again.coins).toBe(0);
    expect((await db.collection(COL.coinLedger).doc(old).get()).get("expired")).toBe(true);
    expect((await db.collection(COL.coinLedger).doc(`expiry:${old}`).get()).get("amount")).toBe(-5);
  });
});

describe("Roles, suspension, quests", () => {
  const org = `${C}-org2`;
  beforeAll(async () => {
    await makeCampus(C);
    await makeUser(C, admin, ["student", "campus_admin"]);
    await makeUser(C, org, ["student", "organizer"]);
    await makeUser(C, `${C}-brand`, ["student"]);
    await makeUser(C, `${C}-s1`);
    await makeUser(C, `${C}-s2`);
    await db.collection(COL.brandAccounts).doc("brandX").set({ name: "BrandX", status: "active" });
    await db.collection(COL.brandMemberships).doc(ids.brandMembership("brandX", `${C}-brand`)).set({ brandId: "brandX", uid: `${C}-brand`, status: "active" });
  });

  it("students cannot grant themselves roles; admins can, audited", async () => {
    await expectDomainError(setMembershipRole.run(asUser(`${C}-s1`, undefined, { campusId: C, uid: `${C}-s1`, role: "organizer", grant: true })), "permission_denied");
    await expectDomainError(setMembershipRole.run(asUser(admin, undefined, { campusId: C, uid: admin, role: "organizer", grant: true })), "permission_denied");
    await setMembershipRole.run(asUser(admin, undefined, { campusId: C, uid: `${C}-s1`, role: "organizer", grant: true, clubId: `${C}-club`, reason: "club president" }));
    const m = await db.collection(COL.memberships).doc(ids.membership(C, `${C}-s1`)).get();
    expect(m.get("roles")).toContain("organizer");
    expect(m.get("clubIds")).toContain(`${C}-club`);
    expect((await db.collection(COL.auditLogs).where("action", "==", "role.grant").where("entityId", "==", m.id).get()).size).toBe(1);
    await expectDomainError(setMembershipRole.run(asUser(admin, undefined, { campusId: C, uid: `${C}-s1`, role: "super_admin", grant: true })), "permission_denied");
  });

  it("suspended users cannot participate", async () => {
    await makeEvent(C, "ev-susp");
    await setUserSuspension.run(asUser(admin, undefined, { campusId: C, uid: `${C}-s2`, suspend: true, reason: "fraud review" }));
    await expectDomainError(createRsvp.run(asUser(`${C}-s2`, undefined, { eventId: "ev-susp" })), "account_suspended");
    await setUserSuspension.run(asUser(admin, undefined, { campusId: C, uid: `${C}-s2`, suspend: false, reason: "cleared" }));
    expect(((await createRsvp.run(asUser(`${C}-s2`, undefined, { eventId: "ev-susp" }))) as any).status).toBe("confirmed");
  });

  it("brand quest lifecycle: draft → submitted → approved/live → student completes on verified check-in → aggregate analytics", async () => {
    await makeEvent(C, "ev-quest", { startInMinutes: 5, organizerUid: org });
    const d = (await saveQuestDraft.run(asUser(`${C}-brand`, undefined, { brandId: "brandX", title: "Show up", description: "Attend the event", type: "event_attendance", campusIds: [C], startAt: new Date(Date.now() - 1000).toISOString(), endAt: new Date(Date.now() + 86400000).toISOString(), criteria: { eventIds: ["ev-quest"] }, rewardCoins: 15, campaignValue: 1500 }))) as any;
    await expectDomainError(saveQuestDraft.run(asUser(`${C}-s1`, undefined, { brandId: "brandX", title: "x", description: "x", type: "event_attendance", campusIds: [C], startAt: new Date().toISOString(), endAt: new Date(Date.now() + 1000).toISOString(), rewardCoins: 1 })), "permission_denied");
    await expectDomainError(joinQuest.run(asUser(`${C}-s1`, undefined, { questId: d.questId })), "quest_not_live");
    await submitBrandQuest.run(asUser(`${C}-brand`, undefined, { questId: d.questId }));
    await expectDomainError(approveBrandQuest.run(asUser(`${C}-brand`, undefined, { questId: d.questId })), "permission_denied");
    const a = (await approveBrandQuest.run(asUser(admin, undefined, { questId: d.questId }))) as any;
    expect(a.status).toBe("live");
    await joinQuest.run(asUser(`${C}-s1`, undefined, { questId: d.questId }));
    const before = await balance(`${C}-s1`);
    await startEventCheckin.run(asUser(org, undefined, { eventId: "ev-quest" }));
    const t = (await issueEventQrToken.run(asUser(org, undefined, { eventId: "ev-quest" }))) as any;
    await checkInWithQr.run(asUser(`${C}-s1`, undefined, { token: t.token }));
    expect(await balance(`${C}-s1`)).toBe(before + 20 + 15);
    const comp = await db.collection(COL.questCompletions).doc(ids.questCompletion(d.questId, `${C}-s1`)).get();
    expect(comp.get("status")).toBe("completed");
    const an = (await getBrandQuestAnalytics.run(asUser(`${C}-brand`, undefined, { questId: d.questId }))) as any;
    expect(an.completions).toBe(1);
    expect(an.joins).toBe(1);
    expect(an.costPerVerifiedAction).toBe(1500);
    // small groups are suppressed for brands
    expect(Object.values(an.tribeBreakdown).every((v) => v === null)).toBe(true);
    await expectDomainError(getBrandQuestAnalytics.run(asUser(`${C}-s1`, undefined, { questId: d.questId })), "permission_denied");
  });
});
