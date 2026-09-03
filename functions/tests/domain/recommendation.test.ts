import { describe, expect, it } from "vitest";
import { DEFAULT_RECOMMENDATION_WEIGHTS } from "../../src/config/defaults";
import { feedVariantFor, rankEvents } from "../../src/domain/recommendation";
import { humanCode, referralCodeFor, searchTokens } from "../../src/domain/search";
import type { EventForRanking } from "../../src/domain/types";

const now = 1_800_000_000_000;
const ev = (id: string, o: Partial<EventForRanking>): EventForRanking => ({ eventId: id, tribeIds: [], tags: [], startAtMs: now + 5 * 86400000, rsvpCount: 0, friendRsvpCount: 0, weekday: 3, hour: 18, ...o });

describe("recommendation", () => {
  const user = { tribeIds: ["finance"], attendedTags: { finance: 3, workshop: 1 }, attendedWeekdays: { "3": 4 }, attendedHourBuckets: { evening: 4 } };

  it("ranks tribe-matching events first with reason codes", () => {
    const r = rankEvents([ev("a", {}), ev("b", { tribeIds: ["finance"] })], user, DEFAULT_RECOMMENDATION_WEIGHTS, now);
    expect(r[0].eventId).toBe("b");
    expect(r[0].reasons).toContain("because_of_tribe");
    expect(r[0].reasons).toContain("similar_to_attended");
  });

  it("boosts imminent events and friends", () => {
    const r = rankEvents([ev("soon", { startAtMs: now + 3600000 }), ev("friends", { friendRsvpCount: 2 }), ev("plain", {})], { tribeIds: [], attendedTags: {}, attendedWeekdays: {}, attendedHourBuckets: {} }, DEFAULT_RECOMMENDATION_WEIGHTS, now);
    expect(r.map((x) => x.eventId)).toEqual(["soon", "friends", "plain"]);
    expect(r[0].reasons).toContain("happening_soon");
    expect(r[1].reasons).toContain("friends_attending");
  });

  it("marks popular events", () => {
    const r = rankEvents([ev("pop", { rsvpCount: 40 }), ev("x", { rsvpCount: 2 })], { tribeIds: [], attendedTags: {}, attendedWeekdays: {}, attendedHourBuckets: {} }, DEFAULT_RECOMMENDATION_WEIGHTS, now);
    expect(r[0].eventId).toBe("pop");
    expect(r[0].reasons).toContain("popular_on_campus");
  });

  it("is deterministic and honours weights", () => {
    const zero = { ...DEFAULT_RECOMMENDATION_WEIGHTS, tribeAffinity: 0, categoryAffinity: 0 };
    const r = rankEvents([ev("a", { startAtMs: now + 1000 }), ev("b", { tribeIds: ["finance"] })], user, zero, now);
    expect(r[0].eventId).toBe("a");
  });

  it("A/B assignment is stable per uid", () => {
    expect(feedVariantFor("user-1")).toBe(feedVariantFor("user-1"));
    const variants = new Set(Array.from({ length: 200 }, (_, i) => feedVariantFor(`u${i}`)));
    expect(variants.size).toBe(2);
    expect(feedVariantFor("any", 1)).toBe("personalized");
    expect(feedVariantFor("any", 0)).toBe("chronological");
  });
});

describe("search helpers", () => {
  it("builds prefix tokens", () => {
    const t = searchTokens("Finance Fest", "Trading workshop");
    expect(t).toContain("finance");
    expect(t).toContain("fin");
    expect(t).toContain("workshop");
    expect(t).not.toContain("a");
  });
  it("referral codes are deterministic", () => {
    expect(referralCodeFor("uid1", "Priya")).toBe(referralCodeFor("uid1", "Priya"));
    expect(referralCodeFor("uid1", "Priya")).toMatch(/^PRIY\d{4}$/);
  });
  it("human codes avoid ambiguous characters", () => {
    const c = humanCode(8, () => 0.999);
    expect(c).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(c).not.toMatch(/[01IO]/);
  });
});
