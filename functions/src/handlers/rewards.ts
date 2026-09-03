import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { REDEMPTION_CODE_TTL_DAYS } from "../config/defaults";
import { fail } from "../domain/errors";
import { humanCode } from "../domain/search";
import { monthKey } from "../domain/time";
import type { RewardType } from "../domain/types";
import { track } from "../lib/analytics";
import { writeAudit } from "../lib/audit";
import { callableHandler, num, requireAuth, requireMembership, str } from "../lib/auth";
import { loadCampus, requireFlag } from "../lib/campus";
import { db, inc, serverTs, Timestamp, toDate, tsToMs } from "../lib/firestore";
import { ledgerEntryExists, readBalance, writeCredit, writeDebit } from "../lib/ledger";
import { enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

const REWARD_TYPES: RewardType[] = ["voucher", "printing_credit", "priority_access", "merchandise", "certificate", "generic"];

/**
 * Transactional redemption: validate reward, inventory, per-user limit, balance;
 * debit ledger; decrement inventory; issue code. No double-spend: the ledger key
 * is the redemption id and inventory is decremented inside the same transaction.
 */
export const redeemReward = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const rewardId = str(req.data?.rewardId, "rewardId");
    const campusId = actor.user?.activeCampusId as string;
    await requireMembership(actor, campusId);
    await requireFlag(campusId, "rewards_enabled");
    const campus = await loadCampus(campusId);
    const rewardRef = db.collection(COL.rewards).doc(rewardId);
    const redemptionRef = db.collection(COL.redemptions).doc();
    const key = ids.ledger.redemption(redemptionRef.id);

    const out = await db.runTransaction(async (tx) => {
      const [reward, balance, userCount, exists] = await Promise.all([
        tx.get(rewardRef),
        readBalance(tx, actor.uid),
        tx.get(db.collection(COL.redemptions).where("rewardId", "==", rewardId).where("uid", "==", actor.uid).where("status", "in", ["issued", "fulfilled"])),
        ledgerEntryExists(tx, key),
      ]);
      if (!reward.exists || reward.get("campusId") !== campusId) fail("not_found", "Reward not found.");
      const r = reward.data()!;
      const nowMs = Date.now();
      if (r.status !== "active") fail("reward_inactive", "This reward isn't available right now.");
      if (r.activeFrom && nowMs < (tsToMs(r.activeFrom) ?? 0)) fail("reward_inactive", "This reward isn't available yet.");
      if (r.activeUntil && nowMs > (tsToMs(r.activeUntil) ?? 0)) fail("reward_inactive", "This reward has ended.");
      const inventory = Number(r.inventory ?? 0);
      if (r.inventory !== null && inventory <= 0) fail("reward_out_of_stock", "This reward is sold out.");
      const perUser = Number(r.perUserLimit ?? 0);
      if (perUser > 0 && userCount.size >= perUser) fail("reward_limit_reached", "You've hit the limit for this reward.");
      const cost = Number(r.coinCost ?? 0);
      if (cost < 0) fail("invalid_argument");
      if (r.type === "certificate") fail("invalid_argument", "Certificates are issued from your participation history.");
      if (balance < cost) fail("insufficient_coins", `You need ${cost - balance} more BuzzCoins for this reward.`, { shortfall: cost - balance });

      if (cost > 0) writeDebit(tx, { key, uid: actor.uid, campusId, type: "debit", reason: "redemption", amount: cost, refId: redemptionRef.id, alreadyExists: exists, currentBalance: balance, economyVersion: campus.economy.version, meta: { rewardId, title: r.title } });
      if (r.inventory !== null) tx.update(rewardRef, { inventory: inc(-1), "stats.redeemed": inc(1) });
      else tx.update(rewardRef, { "stats.redeemed": inc(1) });
      const code = humanCode();
      const expiresAt = new Date(nowMs + (Number(r.redemptionExpiryDays ?? REDEMPTION_CODE_TTL_DAYS)) * 86400000);
      tx.set(redemptionRef, {
        uid: actor.uid,
        campusId,
        rewardId,
        rewardTitle: r.title,
        rewardType: r.type,
        vendorId: r.vendorId ?? null,
        coinCost: cost,
        faceValue: r.faceValue ?? null,
        code,
        status: "issued",
        issuedAt: serverTs(),
        expiresAt: Timestamp.fromDate(expiresAt),
        fulfilledAt: null,
        fulfilledBy: null,
        settlementStatus: "pending",
        settlementMonth: null,
        redemptionInstructions: r.redemptionInstructions ?? null,
      });
      return { code, cost, title: r.title as string, expiresAt };
    });
    await track("reward_redeemed", { uid: actor.uid, campusId, rewardId, coins: out.cost });
    await enqueueNotification({ uid: actor.uid, campusId, category: "transactional", title: "Reward unlocked", body: `${out.title} · code ${out.code}`, route: `/rewards/redemptions/${redemptionRef.id}`, dedupeKey: `redemption:${redemptionRef.id}` });
    return { redemptionId: redemptionRef.id, code: out.code, coinsDebited: out.cost, expiresAt: out.expiresAt.toISOString() };
  }),
);

async function requireVendorForRedemption(req: Parameters<typeof requireAuth>[0], code: string) {
  const actor = await requireAuth(req);
  const snap = await db.collection(COL.redemptions).where("code", "==", code.toUpperCase().trim()).limit(1).get();
  if (snap.empty) fail("redemption_invalid", "No redemption matches that code.");
  const red = snap.docs[0];
  const m = await requireMembership(actor, red.get("campusId"), ["vendor", "campus_admin"]);
  if (m.roles.includes("vendor") && !m.roles.includes("campus_admin") && m.vendorId !== red.get("vendorId")) {
    fail("permission_denied", "This code belongs to a different partner.");
  }
  return { actor, red };
}

/** Vendor validates a code (read-only check). */
export const validateRedemption = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const code = str(req.data?.code, "code", { max: 20 });
    const { red } = await requireVendorForRedemption(req, code);
    const expired = (tsToMs(red.get("expiresAt")) ?? 0) < Date.now();
    return { redemptionId: red.id, status: expired && red.get("status") === "issued" ? "expired" : red.get("status"), rewardTitle: red.get("rewardTitle"), faceValue: red.get("faceValue"), issuedAt: tsToMs(red.get("issuedAt")), valid: red.get("status") === "issued" && !expired };
  }),
);

/** Vendor marks a redemption fulfilled → settlement record. Idempotent. */
export const fulfillRedemption = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const code = str(req.data?.code, "code", { max: 20 });
    const { actor, red } = await requireVendorForRedemption(req, code);
    const campus = await loadCampus(red.get("campusId"));
    const result = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(red.ref);
      if (fresh.get("status") === "fulfilled") return "already";
      if (fresh.get("status") !== "issued") fail("redemption_invalid", `This redemption is ${fresh.get("status")}.`);
      if ((tsToMs(fresh.get("expiresAt")) ?? 0) < Date.now()) fail("redemption_invalid", "This code has expired.");
      tx.update(red.ref, { status: "fulfilled", fulfilledAt: serverTs(), fulfilledBy: actor.uid, settlementMonth: monthKey(new Date(), campus.timezone) });
      tx.set(db.collection(COL.rewards).doc(fresh.get("rewardId")), { "stats.fulfilled": inc(1) }, { merge: true });
      if (fresh.get("vendorId")) tx.set(db.collection(COL.vendors).doc(fresh.get("vendorId")), { "stats.fulfilled": inc(1), "stats.pendingSettlementValue": inc(Number(fresh.get("faceValue") ?? 0)) }, { merge: true });
      return "fulfilled";
    });
    if (result === "fulfilled") await track("redemption_fulfilled", { uid: red.get("uid"), campusId: red.get("campusId"), rewardId: red.get("rewardId"), vendorId: red.get("vendorId") });
    return { status: result };
  }),
);

/** Campus admin creates/updates rewards — inventory edits are audited. */
export const upsertReward = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const rewardId = str(req.data?.rewardId, "rewardId", { optional: true });
    const d = req.data ?? {};
    const type = str(d.type, "type") as RewardType;
    if (!REWARD_TYPES.includes(type)) fail("invalid_argument", "Unknown reward type.");
    const doc = {
      campusId,
      vendorId: str(d.vendorId, "vendorId", { optional: true }) || null,
      title: str(d.title, "title", { max: 100 }),
      description: str(d.description, "description", { max: 1000, optional: true }),
      type,
      coinCost: num(d.coinCost, "coinCost", { min: 0, max: 100000, int: true }),
      inventory: d.inventory === null ? null : num(d.inventory, "inventory", { min: 0, max: 1000000, int: true }),
      faceValue: d.faceValue === undefined || d.faceValue === null ? null : num(d.faceValue, "faceValue", { min: 0 }),
      imageUrl: str(d.imageUrl, "imageUrl", { optional: true, max: 2000 }) || null,
      terms: str(d.terms, "terms", { optional: true, max: 2000 }),
      redemptionInstructions: str(d.redemptionInstructions, "redemptionInstructions", { optional: true, max: 1000 }),
      perUserLimit: num(d.perUserLimit, "perUserLimit", { optional: true, min: 0, max: 100, int: true }),
      activeFrom: toDate(d.activeFrom) ? Timestamp.fromDate(toDate(d.activeFrom)!) : null,
      activeUntil: toDate(d.activeUntil) ? Timestamp.fromDate(toDate(d.activeUntil)!) : null,
      redemptionExpiryDays: num(d.redemptionExpiryDays, "redemptionExpiryDays", { optional: true, min: 1, max: 365, int: true }) || REDEMPTION_CODE_TTL_DAYS,
      status: (str(d.status, "status", { optional: true }) || "active") as "active" | "inactive",
      updatedAt: serverTs(),
    };
    const ref = rewardId ? db.collection(COL.rewards).doc(rewardId) : db.collection(COL.rewards).doc();
    await db.runTransaction(async (tx) => {
      const prev = await tx.get(ref);
      if (prev.exists && prev.get("campusId") !== campusId) fail("permission_denied");
      tx.set(ref, { ...doc, ...(prev.exists ? {} : { createdAt: serverTs(), stats: { redeemed: 0, fulfilled: 0 } }) }, { merge: true });
      writeAudit({ actorUid: actor.uid, action: prev.exists ? "reward.update" : "reward.create", entityType: "reward", entityId: ref.id, campusId, before: prev.exists ? { inventory: prev.get("inventory"), coinCost: prev.get("coinCost"), status: prev.get("status") } : null, after: { inventory: doc.inventory, coinCost: doc.coinCost, status: doc.status } }, tx);
    });
    return { rewardId: ref.id };
  }),
);

/** Manual coin adjustment: privileged, reason required, immutable ledger entry + audit. */
export const adminAdjustCoins = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const targetUid = str(req.data?.uid, "uid");
    const amount = num(req.data?.amount, "amount", { int: true, min: -100000, max: 100000 });
    const reason = str(req.data?.reason, "reason", { max: 500 });
    if (amount === 0) fail("invalid_argument", "Amount can't be zero.");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const campus = await loadCampus(campusId);
    const adjId = db.collection(COL.auditLogs).doc().id;
    const key = ids.ledger.adjustment(adjId);
    await db.runTransaction(async (tx) => {
      const balance = await readBalance(tx, targetUid);
      if (amount > 0) writeCredit(tx, { key, uid: targetUid, campusId, type: "credit", reason: "admin_adjustment", amount, refId: adjId, economy: campus.economy, alreadyExists: false, meta: { reason, actorUid: actor.uid } });
      else writeDebit(tx, { key, uid: targetUid, campusId, type: "adjustment", reason: "admin_adjustment", amount, refId: adjId, alreadyExists: false, currentBalance: balance, economyVersion: campus.economy.version, meta: { reason, actorUid: actor.uid } });
      writeAudit({ actorUid: actor.uid, action: "coins.adjust", entityType: "user", entityId: targetUid, campusId, reason, before: { balance }, after: { balance: balance + amount, ledgerKey: key } }, tx);
    });
    return { ledgerKey: key };
  }),
);

/** Recompute a user's balance from the ledger and repair drift (audited if changed). */
export const reconcileCoinBalance = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const targetUid = str(req.data?.uid, "uid", { optional: true }) || actor.uid;
    if (targetUid !== actor.uid) {
      const campusId = str(req.data?.campusId, "campusId");
      await requireMembership(actor, campusId, ["campus_admin"]);
    }
    const ledger = await db.collection(COL.coinLedger).where("uid", "==", targetUid).select("amount", "type", "reason").get();
    let balance = 0, earned = 0, redeemed = 0, expired = 0;
    for (const d of ledger.docs) {
      const a = Number(d.get("amount"));
      balance += a;
      if (d.get("type") === "credit") earned += a;
      if (d.get("reason") === "redemption") redeemed += -a;
      if (d.get("type") === "expiry") expired += -a;
    }
    const ref = db.collection(COL.coinBalances).doc(targetUid);
    const prev = await ref.get();
    const drift = Number(prev.get("balance") ?? 0) - balance;
    await ref.set({ uid: targetUid, balance, lifetimeEarned: earned, lifetimeRedeemed: redeemed, lifetimeExpired: expired, lastReconciledAt: serverTs(), updatedAt: serverTs() }, { merge: true });
    if (drift !== 0) writeAudit({ actorUid: actor.uid, action: "coins.reconcile", entityType: "user", entityId: targetUid, campusId: prev.get("campusId") ?? null, before: { balance: prev.get("balance") }, after: { balance }, meta: { drift } });
    return { balance, drift };
  }),
);

/** Refund a redemption (admin) — e.g. vendor could not honour it. Credits coins back once. */
export const refundRedemption = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const redemptionId = str(req.data?.redemptionId, "redemptionId");
    const reason = str(req.data?.reason, "reason", { max: 500 });
    const ref = db.collection(COL.redemptions).doc(redemptionId);
    const pre = await ref.get();
    if (!pre.exists) fail("not_found");
    await requireMembership(actor, pre.get("campusId"), ["campus_admin"]);
    const campus = await loadCampus(pre.get("campusId"));
    const key = `refund:${redemptionId}`;
    await db.runTransaction(async (tx) => {
      const [snap, exists] = await Promise.all([tx.get(ref), ledgerEntryExists(tx, key)]);
      if (snap.get("status") === "fulfilled") fail("redemption_invalid", "Fulfilled redemptions can't be refunded.");
      if (snap.get("status") === "cancelled") return;
      tx.update(ref, { status: "cancelled", cancelledAt: serverTs(), cancelReason: reason, cancelledBy: actor.uid });
      if (snap.get("rewardId")) tx.set(db.collection(COL.rewards).doc(snap.get("rewardId")), { inventory: inc(1), "stats.redeemed": inc(-1) }, { merge: true });
      writeCredit(tx, { key, uid: snap.get("uid"), campusId: snap.get("campusId"), type: "credit", reason: "redemption_refund", amount: Number(snap.get("coinCost") ?? 0), refId: redemptionId, economy: campus.economy, alreadyExists: exists, meta: { reason } });
      writeAudit({ actorUid: actor.uid, action: "redemption.refund", entityType: "redemption", entityId: redemptionId, campusId: snap.get("campusId"), reason, before: { status: snap.get("status") }, after: { status: "cancelled" } }, tx);
    });
    return { ok: true };
  }),
);
