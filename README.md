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

Prerequisites: Flutter stable (3.47+), Node 22, Java 17+ (emulators), `npm i -g firebase-tools`.

```bash
flutter pub get
cd functions && npm install && npm run build && cd ..

# terminal 1 — emulators (auth, firestore, functions, storage, UI at :4000)
firebase emulators:start --project demo-campusbuzz

# terminal 2 — deterministic demo campus (emulator only; refuses to run elsewhere)
cd functions && npm run seed && cd ..

# terminal 3 — the app
flutter run -d chrome --dart-define=USE_EMULATORS=true --dart-define=CB_ENV=development
# Android emulator: flutter run -d android --dart-define=USE_EMULATORS=true   (10.0.2.2 is used automatically)
```

Or simply `make setup && make emulators` / `make seed` / `make run-web`.

Demo accounts (emulator only, password `CampusBuzz!123`): `student@`, `organizer@`,
`ambassador@`, `admin@`, `brand@`, `vendor@`, `superadmin@` `demo.campusbuzz.test`.
Follow `docs/DEMO_SCRIPT.md`.

## Validate

```bash
flutter analyze && flutter test
cd functions && npm run lint && npm test && npm run build
# emulator-backed callable integration + Firestore rules tests
firebase emulators:exec --only firestore,auth --project demo-campusbuzz \
  "cd functions && FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 GCLOUD_PROJECT=demo-campusbuzz npx vitest run tests/integration tests/rules"
```

`make test` runs the whole gate; `.github/workflows/ci.yml` runs it on every PR
without any production secret.

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
