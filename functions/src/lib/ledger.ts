import { COL } from "../config/collections";
import { expiresAt as computeExpiry } from "../domain/economy";
import { fail } from "../domain/errors";
import type { EconomyConfig, LedgerEntryInput } from "../domain/types";
import { db, inc, serverTs, Timestamp } from "./firestore";

/**
 * Immutable ledger + materialized balance. Every function here MUST run inside the
 * caller's transaction; the ledger doc id is the idempotency key, so a retried
 * function can never double-award.
 *
 * Read phase (`prepareCredit`) must happen before any writes in the transaction.
 */

export interface PreparedLedgerWrite {
  key: string;
  alreadyExists: boolean;
}

export async function ledgerEntryExists(tx: FirebaseFirestore.Transaction, key: string): Promise<boolean> {
  const snap = await tx.get(db.collection(COL.coinLedger).doc(key));
  return snap.exists;
}

export async function readBalance(tx: FirebaseFirestore.Transaction, uid: string): Promise<number> {
  const snap = await tx.get(db.collection(COL.coinBalances).doc(uid));
  return snap.exists ? Number(snap.get("balance") ?? 0) : 0;
}

/** Write a credit entry (idempotent by key). Returns amount actually credited (0 if duplicate). */
export function writeCredit(
  tx: FirebaseFirestore.Transaction,
  input: LedgerEntryInput & { alreadyExists: boolean; economy: EconomyConfig; createdAt?: Date },
): number {
  if (input.alreadyExists) return 0;
  if (input.amount <= 0) return 0;
  const createdAt = input.createdAt ?? new Date();
  const exp = computeExpiry(createdAt, input.economy);
  tx.set(db.collection(COL.coinLedger).doc(input.key), {
    key: input.key,
    uid: input.uid,
    campusId: input.campusId,
    type: "credit",
    reason: input.reason,
    amount: input.amount,
    remaining: input.amount,
    refId: input.refId ?? null,
    meta: input.meta ?? {},
    economyVersion: input.economy.version,
    expiresAt: exp ? Timestamp.fromDate(exp) : null,
    expired: false,
    createdAt: Timestamp.fromDate(createdAt),
  });
  tx.set(
    db.collection(COL.coinBalances).doc(input.uid),
    {
      uid: input.uid,
      campusId: input.campusId,
      balance: inc(input.amount),
      lifetimeEarned: inc(input.amount),
      updatedAt: serverTs(),
    },
    { merge: true },
  );
  return input.amount;
}

/**
 * Debit (redemption). Caller must have read balance in the same transaction and
 * verified sufficiency; we re-check here defensively.
 */
export function writeDebit(
  tx: FirebaseFirestore.Transaction,
  input: LedgerEntryInput & { alreadyExists: boolean; currentBalance: number; economyVersion: number },
): number {
  if (input.alreadyExists) return 0;
  const amount = Math.abs(input.amount);
  if (amount <= 0) fail("invalid_argument", "Debit must be positive");
  if (input.currentBalance < amount) fail("insufficient_coins", undefined, { shortfall: amount - input.currentBalance });
  tx.set(db.collection(COL.coinLedger).doc(input.key), {
    key: input.key,
    uid: input.uid,
    campusId: input.campusId,
    type: input.type === "adjustment" ? "adjustment" : "debit",
    reason: input.reason,
    amount: -amount,
    refId: input.refId ?? null,
    meta: input.meta ?? {},
    economyVersion: input.economyVersion,
    createdAt: serverTs(),
  });
  tx.set(
    db.collection(COL.coinBalances).doc(input.uid),
    {
      uid: input.uid,
      campusId: input.campusId,
      balance: inc(-amount),
      lifetimeRedeemed: input.reason === "redemption" ? inc(amount) : inc(0),
      updatedAt: serverTs(),
    },
    { merge: true },
  );
  return amount;
}

/** Expiry entry for a credit's remaining portion. Marks the credit as expired. */
export function writeExpiry(
  tx: FirebaseFirestore.Transaction,
  input: { creditKey: string; uid: string; campusId: string; remaining: number; alreadyExists: boolean },
): number {
  if (input.alreadyExists || input.remaining <= 0) return 0;
  tx.set(db.collection(COL.coinLedger).doc(`expiry:${input.creditKey}`), {
    key: `expiry:${input.creditKey}`,
    uid: input.uid,
    campusId: input.campusId,
    type: "expiry",
    reason: "expiry",
    amount: -input.remaining,
    refId: input.creditKey,
    meta: {},
    createdAt: serverTs(),
  });
  tx.update(db.collection(COL.coinLedger).doc(input.creditKey), { remaining: 0, expired: true, expiredAt: serverTs() });
  tx.set(
    db.collection(COL.coinBalances).doc(input.uid),
    { balance: inc(-input.remaining), lifetimeExpired: inc(input.remaining), updatedAt: serverTs() },
    { merge: true },
  );
  return input.remaining;
}
