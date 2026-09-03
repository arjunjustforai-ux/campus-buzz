import { describe, expect, it } from "vitest";
import { DEFAULT_ECONOMY } from "../../src/config/defaults";
import { EMPTY_STREAK, effectiveStreak, multiplierAppliesForCheckin, updateStreak } from "../../src/domain/streaks";
import { isoWeekKey, previousWeekKey, weeksBetween } from "../../src/domain/time";

const TZ = "Asia/Kolkata";

describe("streaks", () => {
  it("first participation starts a streak of 1", () => {
    const s = updateStreak(EMPTY_STREAK, new Date("2026-09-01T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    expect(s.streak).toBe(1);
    expect(s.lastWeekKey).toBe("2026-W36");
    expect(s.multiplierActive).toBe(false);
  });

  it("same week does not increase the streak", () => {
    const s1 = updateStreak(EMPTY_STREAK, new Date("2026-09-01T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    const s2 = updateStreak(s1, new Date("2026-09-04T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    expect(s2.streak).toBe(1);
  });

  it("three consecutive weeks unlock the 2x multiplier", () => {
    let s = updateStreak(EMPTY_STREAK, new Date("2026-09-01T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    s = updateStreak(s, new Date("2026-09-08T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    expect(s.streak).toBe(2);
    expect(multiplierAppliesForCheckin(s, DEFAULT_ECONOMY)).toBe(false);
    s = updateStreak(s, new Date("2026-09-15T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    expect(s.streak).toBe(3);
    expect(s.multiplierActive).toBe(true);
    expect(multiplierAppliesForCheckin(s, DEFAULT_ECONOMY)).toBe(true);
    s = updateStreak(s, new Date("2026-09-22T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    expect(s.streak).toBe(4);
    expect(s.multiplierActive).toBe(true);
  });

  it("missing a full week resets to 1", () => {
    let s = updateStreak(EMPTY_STREAK, new Date("2026-09-01T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    s = updateStreak(s, new Date("2026-09-08T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    s = updateStreak(s, new Date("2026-09-22T10:00:00Z"), TZ, DEFAULT_ECONOMY);
    expect(s.streak).toBe(1);
    expect(s.multiplierActive).toBe(false);
  });

  it("uses the campus timezone to decide the week boundary", () => {
    // Sunday 23:30 IST = Sunday 18:00 UTC → still week 36 in IST; Monday 00:30 IST = Sunday 19:00 UTC → week 37 in IST.
    const sunLateIst = new Date("2026-09-06T18:00:00Z");
    const monEarlyIst = new Date("2026-09-06T19:00:00Z");
    expect(isoWeekKey(sunLateIst, TZ)).toBe("2026-W36");
    expect(isoWeekKey(monEarlyIst, TZ)).toBe("2026-W37");
    expect(isoWeekKey(monEarlyIst, "UTC")).toBe("2026-W36");
  });

  it("configurable threshold", () => {
    const cfg = { ...DEFAULT_ECONOMY, streakThresholdWeeks: 2 };
    let s = updateStreak(EMPTY_STREAK, new Date("2026-09-01T10:00:00Z"), TZ, cfg);
    s = updateStreak(s, new Date("2026-09-08T10:00:00Z"), TZ, cfg);
    expect(s.multiplierActive).toBe(true);
  });

  it("effective streak is 0 after a missed week", () => {
    const s = { streak: 3, lastWeekKey: "2026-W36", multiplierActive: true };
    expect(effectiveStreak(s, new Date("2026-09-10T00:00:00Z"), TZ)).toBe(3); // W37 — still valid
    expect(effectiveStreak(s, new Date("2026-09-20T00:00:00Z"), TZ)).toBe(0); // W38 — broken
  });

  it("week key helpers", () => {
    expect(previousWeekKey("2026-W01")).toBe("2025-W52");
    expect(weeksBetween("2025-W52", "2026-W01")).toBe(1);
    expect(weeksBetween("2026-W36", "2026-W36")).toBe(0);
    expect(weeksBetween("2026-W36", "2026-W38")).toBe(2);
  });
});
