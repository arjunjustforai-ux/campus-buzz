import { describe, expect, it } from "vitest";
import { DEFAULT_PILOT } from "../../src/config/defaults";
import { campusBuzzScore } from "../../src/domain/buzzScore";
import { discoveryConversion, nps, organizerSupplyHealth, redemptionRates, repeatAttendeeRate, rsvpToAttendance, wapRatio, week6Retention, weeklyActiveParticipants, wouldMissPercent } from "../../src/domain/metrics";
import { bandFor, buildScorecard } from "../../src/domain/scorecard";

describe("core metrics", () => {
  it("WAP counts unique users with a verified check-in", () => {
    expect(weeklyActiveParticipants([{ uid: "a" }, { uid: "a" }, { uid: "b" }])).toBe(2);
    expect(wapRatio(45, 150)).toBe(30);
    expect(wapRatio(0, 0)).toBe(0);
  });

  it("conversion formulas", () => {
    expect(rsvpToAttendance(40, 100)).toBe(40);
    expect(rsvpToAttendance(1, 0)).toBe(0);
    expect(discoveryConversion(30, 120)).toBe(25);
  });

  it("redemption rate reports both coin and user based values", () => {
    expect(redemptionRates({ coinsRedeemed: 300, coinsEarned: 1000, usersRedeemed: 10, usersEarned: 40 })).toEqual({ byCoins: 30, byUsers: 25 });
  });

  it("NPS uses 9-10 promoters, 7-8 passives, 0-6 detractors", () => {
    const r = nps([10, 9, 8, 7, 6, 0, 10, 3]);
    expect(r.promoters).toBe(3);
    expect(r.passives).toBe(2);
    expect(r.detractors).toBe(3);
    expect(r.nps).toBe(0);
    expect(nps([10, 10, 9, 8]).nps).toBe(75);
    expect(nps([]).nps).toBe(0);
    expect(nps([11, -1, 5]).responses).toBe(1);
  });

  it("would-miss counts yes and strongly_yes", () => {
    expect(wouldMissPercent(["yes", "strongly_yes", "no", "unsure"])).toBe(50);
  });

  it("week 6 retention distinguishes product vs participation", () => {
    const r = week6Retention({ cohortUids: ["a", "b", "c", "d"], activeWeek6Uids: ["a", "b", "z"], checkedInWeek6Uids: ["a"] });
    expect(r).toEqual({ product: 50, participation: 25, cohortSize: 4 });
  });

  it("supply health flags", () => {
    const r = organizerSupplyHealth({ organizersPostingThisWeek: 2, eventsPostedThisWeek: 3, eventsNext7Days: 0, eventsTodayTomorrow: 0, weeklyEventsTarget: 8, minEventsTodayTomorrow: 2 });
    expect(r.flags).toEqual(["no_upcoming_events", "empty_feed_risk", "below_weekly_event_target"]);
  });

  it("repeat attendee rate", () => {
    expect(repeatAttendeeRate([1, 2, 3, 1])).toBe(50);
    expect(repeatAttendeeRate([])).toBe(0);
  });
});

describe("pilot scorecard", () => {
  it("never marks green without data", () => {
    expect(bandFor(null, DEFAULT_PILOT.bands.wapPercent)).toBe("no_data");
  });
  it("applies documented bands", () => {
    const b = DEFAULT_PILOT.bands;
    expect(bandFor(74, b.registeredStudents)).toBe("red");
    expect(bandFor(75, b.registeredStudents)).toBe("yellow");
    expect(bandFor(149, b.registeredStudents)).toBe("yellow");
    expect(bandFor(150, b.registeredStudents)).toBe("green");
    expect(bandFor(14.99, b.wapPercent)).toBe("red");
    expect(bandFor(29.99, b.wapPercent)).toBe("yellow");
    expect(bandFor(30, b.wapPercent)).toBe("green");
    expect(bandFor(24, b.week6Retention)).toBe("red");
    expect(bandFor(45, b.week6Retention)).toBe("green");
    expect(bandFor(4, b.organizersPostingWeekly)).toBe("red");
    expect(bandFor(9, b.organizersPostingWeekly)).toBe("yellow");
    expect(bandFor(10, b.organizersPostingWeekly)).toBe("green");
    expect(bandFor(39.99, b.rsvpToAttendance)).toBe("yellow");
    expect(bandFor(40, b.rsvpToAttendance)).toBe("green");
    expect(bandFor(19, b.nps)).toBe("red");
    expect(bandFor(40, b.nps)).toBe("green");
    expect(bandFor(49.99, b.wouldMiss)).toBe("yellow");
    expect(bandFor(50, b.wouldMiss)).toBe("green");
  });
  it("builds all seven rows", () => {
    const rows = buildScorecard({ registeredStudents: 160, wapPercent: 31, week6Retention: null, organizersPostingWeekly: 7, rsvpToAttendance: 42, nps: 45, wouldMiss: 55 }, DEFAULT_PILOT.bands);
    expect(rows).toHaveLength(7);
    expect(rows.map((r) => r.band)).toEqual(["green", "green", "no_data", "yellow", "green", "green", "green"]);
  });
});

describe("campus buzz score", () => {
  it("is a transparent weighted score with components summing to the total", () => {
    const r = campusBuzzScore({ wapPercent: 25, rsvpToAttendance: 50, eventsThisWeek: 4, weeklyEventsTarget: 8, retentionPercent: 40 });
    expect(r.components.map((c) => c.key)).toEqual(["wap", "rsvpToAttendance", "eventSupply", "retention"]);
    const sum = r.components.reduce((s, c) => s + c.contribution, 0);
    expect(r.score).toBe(Math.round(sum));
    expect(r.score).toBe(48); // 0.5*40 + 0.5*20 + 0.5*20 + 0.4*20 = 20+10+10+8
  });
  it("caps at 100", () => {
    expect(campusBuzzScore({ wapPercent: 90, rsvpToAttendance: 100, eventsThisWeek: 20, weeklyEventsTarget: 8, retentionPercent: 100 }).score).toBe(100);
  });
});
