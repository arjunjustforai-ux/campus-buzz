#!/usr/bin/env node
/**
 * CampusBuzz preflight check.  `npm run doctor`
 *
 * Tells you exactly what is missing before you try to run the app, instead of
 * letting it fail later with a vague "You look offline" in the UI.
 * Works on Windows, macOS and Linux.
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { createConnection } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const isWindows = process.platform === "win32";

const OK = "[32m✔[0m";
const BAD = "[31m✘[0m";
const WARN = "[33m![0m";

let failures = 0;
const note = [];

function run(cmd, args) {
  // shell:true so Windows resolves flutter.bat / firebase.cmd from PATH.
  const r = spawnSync(cmd, args, { encoding: "utf8", shell: true, timeout: 90000 });
  if (r.error || r.status !== 0) return null;
  return `${r.stdout ?? ""}${r.stderr ?? ""}`.trim();
}

function check(label, value, { fix, warnOnly = false, detail } = {}) {
  if (value) {
    console.log(`  ${OK} ${label}${detail ? `  ${detail}` : ""}`);
    return true;
  }
  if (warnOnly) {
    console.log(`  ${WARN} ${label}`);
    if (fix) note.push(fix);
    return false;
  }
  console.log(`  ${BAD} ${label}`);
  if (fix) note.push(fix);
  failures++;
  return false;
}

function portInUse(port) {
  return new Promise((resolve) => {
    const socket = createConnection({ host: "127.0.0.1", port });
    const done = (v) => { socket.destroy(); resolve(v); };
    socket.setTimeout(700);
    socket.on("connect", () => done(true));
    socket.on("timeout", () => done(false));
    socket.on("error", () => done(false));
  });
}

console.log("\nCampusBuzz doctor\n");

// ---- Toolchain -------------------------------------------------------------
console.log("Toolchain");

const nodeMajor = Number(process.versions.node.split(".")[0]);
check(`Node.js ${process.versions.node}`, nodeMajor >= 20, {
  fix: `Node 20+ required (found ${process.versions.node}). Install the LTS from https://nodejs.org`,
});

const java = run("java", ["-version"]);
check(
  "Java (required by the Firestore emulator)",
  java,
  { fix: "Install a JDK 17+ from https://adoptium.net, reopen your terminal, then re-run. The Firestore and Pub/Sub emulators are Java programs and will not start without it." },
);

const flutter = run("flutter", ["--version"]);
check("Flutter SDK", flutter, {
  fix: "Install Flutter and add its bin folder to PATH: https://docs.flutter.dev/get-started/install",
  detail: flutter ? flutter.split("\n")[0] : undefined,
});

const firebase = run("firebase", ["--version"]);
check("Firebase CLI", firebase, {
  fix: "Install it with:  npm install -g firebase-tools",
  detail: firebase ? `v${firebase.split("\n")[0]}` : undefined,
});

// ---- Project state ---------------------------------------------------------
console.log("\nProject");

check("functions/node_modules present", existsSync(join(root, "functions", "node_modules")), {
  fix: "Run:  npm run setup",
});

check(
  "Cloud Functions compiled (functions/lib)",
  existsSync(join(root, "functions", "lib", "index.js")),
  { fix: "Run:  npm run setup     (the emulator cannot load functions until they are built)" },
);

check(".dart_tool present (flutter pub get has run)", existsSync(join(root, ".dart_tool")), {
  fix: "Run:  npm run setup",
});

// ---- Emulators -------------------------------------------------------------
console.log("\nEmulator Suite");

const ports = [
  [8080, "Firestore"],
  [9099, "Auth"],
  [5001, "Functions"],
  [4000, "Emulator UI"],
];
const live = [];
for (const [port, name] of ports) {
  if (await portInUse(port)) live.push(`${name}:${port}`);
}

if (live.length === ports.length) {
  console.log(`  ${OK} All emulators are listening (${live.join(", ")})`);
  console.log(`  ${OK} Emulator UI: http://localhost:4000`);
} else if (live.length === 0) {
  console.log(`  ${WARN} No emulators running`);
  note.push("Start them in their own terminal and leave it open:  npm run emulators");
  note.push("Then seed the demo data in a second terminal:        npm run seed");
} else {
  console.log(`  ${WARN} Only some emulators are listening (${live.join(", ")})`);
  note.push("The emulator suite looks partially up. Stop it, then run:  npm run emulators");
}

// ---- Summary ---------------------------------------------------------------
console.log("");
if (failures === 0 && note.length === 0) {
  console.log(`${OK} Everything looks ready.\n`);
  console.log("  1. npm run emulators   (terminal 1, leave running)");
  console.log("  2. npm run seed        (terminal 2, after 'All emulators ready!')");
  console.log("  3. npm run app         (terminal 3)\n");
  console.log("  Sign in with the demo chips on the sign-in screen. Password: CampusBuzz!123\n");
  process.exit(0);
}

console.log(failures > 0 ? "Fix these before running the app:\n" : "Next steps:\n");
for (const n of note) console.log(`  • ${n}`);
console.log("");
if (isWindows) {
  console.log("Windows note: use `npm run ...` (not `make`). All scripts are cross-platform.\n");
}
process.exit(failures > 0 ? 1 : 0);
