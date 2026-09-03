import { describe, expect, it } from "vitest";
import { signToken, verifyToken, windowIndex } from "../../src/domain/qrToken";

const secret = "test-secret-at-least-16-chars";
const base = 1_800_000_000_000; // fixed epoch ms

describe("qr token", () => {
  const payload = { e: "evt1", c: "campus1", w: windowIndex(base), n: "nonce", v: 1 };

  it("round-trips a valid token inside its window", () => {
    const t = signToken(payload, secret);
    const r = verifyToken(t, secret, base + 10_000);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.payload.e).toBe("evt1");
  });

  it("accepts within the 15s grace after rotation, rejects afterwards", () => {
    const t = signToken(payload, secret);
    const windowStart = payload.w * 30_000;
    expect(verifyToken(t, secret, windowStart + 30_000 + 14_000).ok).toBe(true);
    const late = verifyToken(t, secret, windowStart + 30_000 + 16_000);
    expect(late.ok).toBe(false);
    if (!late.ok) expect(late.reason).toBe("expired");
  });

  it("rejects tampered payloads", () => {
    const t = signToken(payload, secret);
    const [body, sig] = t.split(".");
    const tampered = Buffer.from(JSON.stringify({ ...payload, e: "evt2" })).toString("base64url") + "." + sig;
    const r = verifyToken(tampered, secret, base);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("bad_signature");
    expect(verifyToken(body, secret, base).ok).toBe(false);
  });

  it("rejects tokens signed with another secret", () => {
    const t = signToken(payload, "another-secret-value-1234");
    expect(verifyToken(t, secret, base).ok).toBe(false);
  });

  it("rejects malformed and future tokens", () => {
    expect(verifyToken("garbage", secret, base).ok).toBe(false);
    expect(verifyToken("", secret, base).ok).toBe(false);
    const future = signToken({ ...payload, w: payload.w + 5 }, secret);
    const r = verifyToken(future, secret, base);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("expired");
  });

  it("rejects unknown versions", () => {
    const r = verifyToken(signToken({ ...payload, v: 99 }, secret), secret, base);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("version");
  });

  it("rotates every 30 seconds", () => {
    expect(windowIndex(base + 29_999)).toBe(windowIndex(base));
    expect(windowIndex(base + 30_000)).toBe(windowIndex(base) + 1);
  });
});
