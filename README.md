# CampusBuzz

**The Operating System for Campus Culture.** Show up. Earn rewards. Find your tribe.

CampusBuzz is a mobile-first campus participation platform: discovery → identity
(Tribes) → RSVP → verified QR check-in → BuzzCoins → real campus rewards → feedback →
repeat. Organizers get a 60-second posting flow, live rotating QR check-in and real
attendance analytics; campus operations get a pilot scorecard built on the North
Star metric **Weekly Active Participants (WAP)**; brands run verified participation
quests and see only aggregates.

Flutter (Android · iOS · web) + Firebase (Auth, Firestore, Functions in TypeScript,
Storage, FCM, Remote Config, App Check, Crashlytics) with the Emulator Suite for local
development. Every economy- or security-sensitive action is a server-side transaction.

## Run it locally (5 minutes)

Works the same on **Windows, macOS and Linux** — every command below is `npm run`,
so you do not need `make` or a bash shell.

**Install once:** [Node 20+](https://nodejs.org), [Flutter stable](https://docs.flutter.dev/get-started/install),
a [JDK 17+](https://adoptium.net) (the Firestore emulator is a Java program and will not
start without it), then `npm install -g firebase-tools`. You do **not** need a Firebase
account or `firebase login` for this — everything runs on local emulators.

```bash
git clone https://github.com/arjunjustforai-ux/campus-buzz && cd campus-buzz

npm run setup       # flutter pub get + functions install + build
npm run doctor      # checks Node, Java, Flutter, CLI, build state, ports

npm run emulators   # terminal 1 — leave running, wait for "All emulators ready!"
npm run seed        # terminal 2 — creates the demo campus (re-run after each restart)
npm run app         # terminal 3 — opens Chrome
```

On the sign-in screen tap a demo chip (`student`, `organizer`, `admin`, `brand`,
`vendor`, `superadmin`); the password is `CampusBuzz!123`. Emulator UI:
http://localhost:4000. Then follow [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md).

**If something does not work, run `npm run doctor` first** — it names the missing
piece instead of leaving you with a vague error in the UI. The two most common
causes are no JDK installed (emulators never start) and forgetting `npm run seed`
after restarting the emulators, since emulator data is in-memory.

## Validate

```bash
npm run analyze          # flutter analyze + functions lint
npm test                 # flutter test + functions domain tests

# emulator-backed callable integration + Firestore security-rules tests
npm --prefix functions run test:integration
npm --prefix functions run test:rules
```

`.github/workflows/ci.yml` runs the same gate on every PR, with no production secrets.

## Configuration

Copy `.env.example` → `.env` / `.env.json` (see `.env.json.example`) and pass
`--dart-define-from-file=.env.json`. Cloud Functions secrets (`QR_SIGNING_SECRET`)
are set with `firebase functions:secrets:set`. Feature flags (Remote Config +
per-campus overrides) are separate from economy configuration (versioned per campus).

## Documentation

| Doc | Contents |
|---|---|
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | audit, plan, decisions, milestone log |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Flutter/Firebase structure, roles, lifecycles, flows (Mermaid) |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | every collection, ids, invariants, indexes |
| [docs/SECURITY.md](docs/SECURITY.md) | auth, rules, isolation, QR signing, coin integrity, App Check, audit, deletion |
| [docs/ANALYTICS.md](docs/ANALYTICS.md) | instrumentation, metric formulas, scorecard bands, Buzz Score, recommendations |
| [docs/BUZZCOIN_ECONOMY.md](docs/BUZZCOIN_ECONOMY.md) | earning, streaks, FIFO expiry, health thresholds, versioning |
| [docs/QR_CHECKIN.md](docs/QR_CHECKIN.md) | rotating signed tokens, validation, manual fallback |
| [docs/ROLE_PERMISSIONS.md](docs/ROLE_PERMISSIONS.md) | capability matrix |
| [docs/TEST_PLAN.md](docs/TEST_PLAN.md) | test layers, journeys, QA checklist, results |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | environments, staging deploy, credentials |
| [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md) | 12-minute end-to-end demo |
| [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) | what is not done yet |

## Product principles baked in

participation over screen time (no infinite scroll, ≤2 engagement pushes/day) ·
identity before information (Tribes are a primitive) · organizer success = platform
success · low friction (one-tap RSVP, scan-and-confirm) · earn trust, don't spam ·
targets are not traction (dashboards show only stored data; targets are labelled).

License: MIT.
