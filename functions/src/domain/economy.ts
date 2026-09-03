import type { EconomyConfig, LedgerCredit } from "./types";

/**
 * Pure BuzzCoin economy maths. All awarding decisions are made here and executed
 * inside Firestore transactions by lib/ledger.ts.
 */

export function checkinReward(config: EconomyConfig, multiplierActive: boolean): number {
  return multiplierActive ? config.checkinReward * config.streakMultiplier : config.checkinReward;
}

export function organizerBonusEligible(config: EconomyConfig, verifiedAttendees: number): boolean {
  return verifiedAttendees >= config.organizerMinVerifiedAttendees;
}

/** Balance derived purely from ledger entries: credits − debits − expirations. */
export function balanceFromLedger(entries: Array<{ amount: number }>): number {
  return entries.reduce((sum, e) => sum + e.amount, 0);
}

export function expiresAt(createdAt: Date, config: EconomyConfig): Date | null {
  if (!config.coinExpiryDays || config.coinExpiryDays <= 0) return null;
  return new Date(createdAt.getTime() + config.coinExpiryDays * 86400000);
}

/**
 * FIFO consumption: spend `amount` against the oldest credits first, returning the
 * updated credits and the per-credit consumption so redemption debits can be
 * attributed (this is what makes expiry correct — only unspent credit expires).
 */
export function consumeFifo(
  credits: LedgerCredit[],
  amount: number,
): { credits: LedgerCredit[]; consumed: Array<{ key: string; amount: number }> } {
  if (amount <= 0) return { credits, consumed: [] };
  const sorted = [...credits].sort((a, b) => a.createdAtMs - b.createdAtMs);
  let left = amount;
  const consumed: Array<{ key: string; amount: number }> = [];
  const out = sorted.map((c) => {
    if (left <= 0 || c.remaining <= 0) return c;
    const take = Math.min(c.remaining, left);
    left -= take;
    consumed.push({ key: c.key, amount: take });
    return { ...c, remaining: c.remaining - take };
  });
  if (left > 0) throw new Error("insufficient_credit_for_fifo_consumption");
  return { credits: out, consumed };
}

/** Credits whose remaining portion has passed its expiry at `nowMs`. */
export function expiredCredits(credits: LedgerCredit[], nowMs: number): LedgerCredit[] {
  return credits.filter((c) => c.remaining > 0 && c.expiresAtMs !== null && c.expiresAtMs <= nowMs);
}

/** Sum of credit remaining that will expire within `withinDays`. */
export function expiringSoon(credits: LedgerCredit[], nowMs: number, withinDays: number): number {
  const limit = nowMs + withinDays * 86400000;
  return credits
    .filter((c) => c.remaining > 0 && c.expiresAtMs !== null && c.expiresAtMs > nowMs && c.expiresAtMs <= limit)
    .reduce((s, c) => s + c.remaining, 0);
}

export interface EconomyHealthInput {
  coinsEarnedMonth: number;
  coinsRedeemedMonth: number;
  usersEarned: number;
  usersRedeemed: number;
  activeUsersWeek: number;
  coinsEarnedWeek: number;
  redeemableInventoryValueCoins: number;
}

export interface EconomyHealth {
  avgWeeklyEarnPerUser: number;
  redemptionRateCoins: number; // percent
  redemptionRateUsers: number; // percent
  earnedToRedeemableRatio: number;
  warnings: string[];
}

export function economyHealth(
  input: EconomyHealthInput,
  thresholds: {
    weeklyEarnHealthyMin: number;
    weeklyEarnHealthyMax: number;
    weeklyEarnWarning: number;
    redemptionWarning: number;
    maxEarnedToRedeemableRatio: number;
  },
): EconomyHealth {
  const avgWeeklyEarnPerUser = input.activeUsersWeek > 0 ? input.coinsEarnedWeek / input.activeUsersWeek : 0;
  const redemptionRateCoins = input.coinsEarnedMonth > 0 ? (input.coinsRedeemedMonth / input.coinsEarnedMonth) * 100 : 0;
  const redemptionRateUsers = input.usersEarned > 0 ? (input.usersRedeemed / input.usersEarned) * 100 : 0;
  const earnedToRedeemableRatio =
    input.redeemableInventoryValueCoins > 0 ? input.coinsEarnedMonth / input.redeemableInventoryValueCoins : 0;
  const warnings: string[] = [];
  if (avgWeeklyEarnPerUser > thresholds.weeklyEarnWarning) warnings.push("high_weekly_earn");
  if (input.coinsEarnedMonth > 0 && redemptionRateCoins < thresholds.redemptionWarning) warnings.push("low_redemption_rate");
  if (input.redeemableInventoryValueCoins > 0 && earnedToRedeemableRatio > thresholds.maxEarnedToRedeemableRatio) {
    warnings.push("earned_exceeds_redeemable");
  }
  if (input.redeemableInventoryValueCoins === 0 && input.coinsEarnedMonth > 0) warnings.push("no_redeemable_inventory");
  return { avgWeeklyEarnPerUser, redemptionRateCoins, redemptionRateUsers, earnedToRedeemableRatio, warnings };
}
