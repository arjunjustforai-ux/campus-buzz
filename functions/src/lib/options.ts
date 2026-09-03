import type { CallableOptions } from "firebase-functions/v2/https";
import { isEmulator, QR_SIGNING_SECRET } from "../config/secrets";

/** Mumbai region keeps latency low for the JAGSoM pilot; configurable via env. */
export const REGION = process.env.CB_FUNCTIONS_REGION ?? "asia-south1";

/** App Check is enforced everywhere except the emulator (or when explicitly disabled for staging debugging). */
export const ENFORCE_APP_CHECK = !isEmulator() && process.env.APP_CHECK_ENFORCE !== "false";

export const callableOpts: CallableOptions = {
  region: REGION,
  enforceAppCheck: ENFORCE_APP_CHECK,
  memory: "256MiB",
  timeoutSeconds: 60,
};

export const callableOptsWithQrSecret: CallableOptions = {
  ...callableOpts,
  secrets: [QR_SIGNING_SECRET],
};

export const scheduleOpts = { region: REGION, timeoutSeconds: 540, memory: "512MiB" as const };
