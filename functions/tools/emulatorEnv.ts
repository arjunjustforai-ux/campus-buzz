/**
 * Emulator wiring for local tools (seed, one-off scripts).
 *
 * MUST be imported before any firebase-admin module: the Admin SDK reads these
 * variables when the Firestore/Auth clients are constructed, so setting them
 * later has no effect.
 *
 * Defaults are applied here rather than in the npm script so the tools run
 * identically on Windows (cmd.exe), PowerShell, macOS and Linux — `VAR=value cmd`
 * prefixes are POSIX-only and fail on Windows.
 */

/** True when the caller pointed us at an emulator explicitly. */
const explicitFirestore = !!process.env.FIRESTORE_EMULATOR_HOST;
const explicitAuth = !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

process.env.FIRESTORE_EMULATOR_HOST ||= "localhost:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "localhost:9099";
process.env.GCLOUD_PROJECT ||= "demo-campusbuzz";

const project = process.env.GCLOUD_PROJECT;

/**
 * Safety gate. Firebase reserves the `demo-` project prefix for emulator-only
 * projects that can never reach a real backend, so a `demo-` project is safe by
 * construction. Any other project id is only allowed when the caller has
 * explicitly pointed both emulator hosts somewhere themselves.
 */
if (!project.startsWith("demo-") && !(explicitFirestore && explicitAuth)) {
  console.error(
    `Refusing to run against project "${project}".\n` +
      "Local tools only target the Firebase Emulator Suite. Use a `demo-` project id\n" +
      "(the default is demo-campusbuzz), or set FIRESTORE_EMULATOR_HOST and\n" +
      "FIREBASE_AUTH_EMULATOR_HOST explicitly if you know what you are doing.",
  );
  process.exit(1);
}

export const EMULATOR_PROJECT = project;
export const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST!;
export const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST!;
