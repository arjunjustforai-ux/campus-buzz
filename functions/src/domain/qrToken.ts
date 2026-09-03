import { createHmac, timingSafeEqual } from "node:crypto";
import { QR_TOKEN } from "../config/defaults";
import type { QrTokenPayload } from "./types";

/**
 * Rotating, signed check-in tokens.
 * Format: base64url(json payload) + "." + base64url(HMAC-SHA256(payload, secret))
 * The QR image is only a transport for this string; validation is server-side.
 */

export function windowIndex(nowMs: number, rotationSeconds: number = QR_TOKEN.rotationSeconds): number {
  return Math.floor(nowMs / 1000 / rotationSeconds);
}

export function signToken(payload: QrTokenPayload, secret: string): string {
  const body = b64url(Buffer.from(JSON.stringify(payload)));
  const sig = b64url(createHmac("sha256", secret).update(body).digest());
  return `${body}.${sig}`;
}

export type VerifyResult =
  | { ok: true; payload: QrTokenPayload }
  | { ok: false; reason: "malformed" | "bad_signature" | "expired" | "version" };

export function verifyToken(
  token: string,
  secret: string,
  nowMs: number,
  opts: { rotationSeconds?: number; graceSeconds?: number } = {},
): VerifyResult {
  const rotation = opts.rotationSeconds ?? QR_TOKEN.rotationSeconds;
  const grace = opts.graceSeconds ?? QR_TOKEN.graceSeconds;
  const parts = token.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) return { ok: false, reason: "malformed" };
  const [body, sig] = parts;
  const expected = b64url(createHmac("sha256", secret).update(body).digest());
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return { ok: false, reason: "bad_signature" };
  let payload: QrTokenPayload;
  try {
    payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (
    typeof payload?.e !== "string" ||
    typeof payload?.c !== "string" ||
    typeof payload?.w !== "number" ||
    typeof payload?.n !== "string" ||
    typeof payload?.v !== "number"
  ) {
    return { ok: false, reason: "malformed" };
  }
  if (payload.v !== QR_TOKEN.version) return { ok: false, reason: "version" };
  const current = windowIndex(nowMs, rotation);
  // Valid for its own window plus a grace period (covers scan/network latency).
  const windowStartMs = payload.w * rotation * 1000;
  const validUntilMs = windowStartMs + rotation * 1000 + grace * 1000;
  if (payload.w > current + 1) return { ok: false, reason: "expired" }; // clock skew guard: future tokens rejected
  if (nowMs > validUntilMs) return { ok: false, reason: "expired" };
  return { ok: true, payload };
}

function b64url(buf: Buffer): string {
  return buf.toString("base64url");
}
