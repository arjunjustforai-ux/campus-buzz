import { defineSecret, defineString } from "firebase-functions/params";

/** HMAC key for rotating QR tokens. Set with `firebase functions:secrets:set QR_SIGNING_SECRET`. */
export const QR_SIGNING_SECRET = defineSecret("QR_SIGNING_SECRET");

/** Optional server-side PostHog key (analytics abstraction works without it). */
export const POSTHOG_SERVER_KEY = defineString("POSTHOG_SERVER_KEY", { default: "" });

export const isEmulator = (): boolean =>
  process.env.FUNCTIONS_EMULATOR === "true" || !!process.env.FIRESTORE_EMULATOR_HOST;

/**
 * Resolve the QR signing secret. In the emulator a deterministic dev key is used so
 * local demos work with zero setup; in production the secret is mandatory.
 */
export function qrSigningSecret(): string {
  const v = process.env.QR_SIGNING_SECRET || safeSecretValue();
  if (v && v.length >= 16) return v;
  if (isEmulator()) return "campusbuzz-emulator-only-qr-secret-do-not-use-in-prod";
  throw new Error("QR_SIGNING_SECRET is not configured");
}

function safeSecretValue(): string {
  try {
    return QR_SIGNING_SECRET.value();
  } catch {
    return "";
  }
}
