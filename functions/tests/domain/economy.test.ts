import { describe, expect, it } from "vitest";
import { DEFAULT_ECONOMY } from "../../src/config/defaults";
import { balanceFromLedger, checkinReward, consumeFifo, economyHealth, expiredCredits, expiresAt, expiringSoon, organizerBonusEligible } from "../../src/domain/economy";
import type { LedgerCredit } from "../../src/domain/types";

const day = 86400000;

describe("economy", () => {
  it("applies default earning rules", () => {
    expect(DEFAULT_ECONOMY.rsvpReward).toBe(5);
    expect(DEFAULT_ECONOMY.checkinReward).toBe(20);
    expect(DEFAULT_ECONOMY.feedbackReward).toBe(10);
    expect(DEFAULT_ECONOMY.referralReward).toBe(25);
    expect(DEFAULT_ECONOMY.organizerReward).toBe(50);
  });

  it("doubles check-in reward when the streak multiplier is active", () => {
    expect(checkinReward(DEFAULT_ECONOMY, false)).toBe(20);
    expect(checkinReward(DEFAULT_ECONOMY, true)).toBe(40);
    expect(checkinReward({ ...DEFAULT_ECONOMY, streakMultiplier: 3 }, true)).toBe(60);
  });

  it("organizer bonus needs >= 10 verified attendees", () => {
    expect(organizerBonusEligible(DEFAULT_ECONOMY, 9)).toBe(false);
    expect(organizerBonusEligible(DEFAULT_ECONOMY, 10)).toBe(true);
  });

  it("balance = credits - debits - expirations", () => {
    expect(balanceFromLedger([{ amount: 20 }, { amount: 5 }, { amount: -10 }, { amount: -3 }])).toBe(12);
  });

  it("expiry is 90 days by default and disabled when 0", () => {
    const at = new Date("2026-01-01T00:00:00Z");
    expect(expiresAt(at, DEFAULT_ECONOMY)!.getTime()).toBe(at.getTime() + 90 * day);
    expect(expiresAt(at, { ...DEFAULT_ECONOMY, coinExpiryDays: 0 })).toBeNull();
  });

  describe("FIFO", () => {
    const credits: LedgerCredit[] = [
      { key: "b", amount: 20, remaining: 20, createdAtMs: 2000, expiresAtMs: 2000 + 90 * day },
      { key: "a", amount: 5, remaining: 5, createdAtMs: 1000, expiresAtMs: 1000 + 90 * day },
      { key: "c", amount: 10, remaining: 10, createdAtMs: 3000, expiresAtMs: null },
    ];
    it("consumes oldest credits first", () => {
      const r = consumeFifo(credits, 22);
      expect(r.consumed).toEqual([{ key: "a", amount: 5 }, { key: "b", amount: 17 }]);
      expect(r.credits.find((c) => c.key === "b")!.remaining).toBe(3);
      expect(r.credits.find((c) => c.key === "c")!.remaining).toBe(10);
    });
    it("throws when credits are insufficient", () => {
      expect(() => consumeFifo(credits, 100)).toThrow();
    });
    it("only expires the unspent remainder", () => {
      const r = consumeFifo(credits, 22);
      const now = 3000 + 90 * day; // a and b expired, c never expires
      const exp = expiredCredits(r.credits, now);
      expect(exp.map((c) => c.key)).toEqual(["b"]); // a fully consumed → nothing to expire
      expect(exp[0].remaining).toBe(3);
    });
    it("reports expiring-soon totals", () => {
      expect(expiringSoon(credits, 1000, 91)).toBe(25);
      expect(expiringSoon(credits, 1000, 1)).toBe(0);
    });
  });

  describe("health", () => {
    const thresholds = { weeklyEarnHealthyMin: 30, weeklyEarnHealthyMax: 60, weeklyEarnWarning: 80, redemptionWarning: 15, maxEarnedToRedeemableRatio: 3 };
    it("warns on high weekly earn and low redemption", () => {
      const h = economyHealth({ coinsEarnedMonth: 10000, coinsRedeemedMonth: 500, usersEarned: 100, usersRedeemed: 4, activeUsersWeek: 20, coinsEarnedWeek: 2000, redeemableInventoryValueCoins: 2000 }, thresholds);
      expect(h.avgWeeklyEarnPerUser).toBe(100);
      expect(h.warnings).toContain("high_weekly_earn");
      expect(h.warnings).toContain("low_redemption_rate");
      expect(h.warnings).toContain("earned_exceeds_redeemable");
    });
    it("is quiet when healthy", () => {
      const h = economyHealth({ coinsEarnedMonth: 3000, coinsRedeemedMonth: 1000, usersEarned: 100, usersRedeemed: 40, activeUsersWeek: 50, coinsEarnedWeek: 2000, redeemableInventoryValueCoins: 3000 }, thresholds);
      expect(h.warnings).toEqual([]);
      expect(h.redemptionRateCoins).toBeCloseTo(33.33, 1);
    });
  });
});
