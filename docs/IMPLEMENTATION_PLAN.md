# CampusBuzz — Implementation Plan

_Last updated: 2026-09-03 (Milestone progress is appended at the bottom of this file)._

## 1. Current-state assessment

The `arjunjustforai-ux/campus-buzz` repository was audited on 2026-09-03.

| Item | Finding |
|------|---------|
| Directory structure | Empty — only `LICENSE` (MIT) and `.git`. |
| README | None. |
| `pubspec.yaml` | None — no Flutter app. |
| Firebase configuration | None (`firebase.json`, rules, indexes absent). |
| Authentication | None. |
| Firestore models | None. |
| Screens / navigation | None. |
| Cloud Functions | None. |
| Security rules | None. |
| Tests | None. |
| Docs / assets / design | None in repo. Brand direction supplied in the build brief (Deep Orange `#FF5F1F`, Lime `#CDFF57`, Dark `#0A0A0F`, Syne + DM Sans). |
| Runnable application | Nothing to run. |

**Conclusion:** there is no prototype to preserve. The canonical Flutter + Firebase
architecture from the brief is initialised from scratch. No destructive refactor is
needed because nothing exists.

### Existing features
None.

### Missing features
Everything in the brief: auth/campus verification, roles, discovery feed, search,
event lifecycle, RSVP, rotating QR check-in, BuzzCoin ledger, rewards/redemption,
Tribes, leaderboard, feedback, referrals, friends, notifications, organizer tooling,
campus admin console, pilot scorecard, brand quests, vendor portal, multi-campus,
entitlements, analytics, tests, CI, docs, seed data.

### Technical debt
None inherited. Debt we consciously accept is tracked in `docs/KNOWN_LIMITATIONS.md`.

## 2. Proposed architecture

```
Flutter (Riverpod + go_router, Material 3 custom theme)
   │  reads: Firestore (rules-scoped, paginated)      writes: only own low-risk docs
   │  calls: Cloud Functions (callable, App Check)     for every economy/security action
   ▼
Firebase: Auth · Firestore · Storage · Functions (TS) · FCM · Remote Config
          · App Check · Analytics · Crashlytics · Emulator Suite
```

- **Feature-first Flutter modules** under `lib/features/<feature>/{data,domain,application,presentation}`.
- **Server-authoritative domain**: every coin credit/debit, check-in, RSVP, redemption,
  referral, role change, quest approval and admin config change is a Cloud Function
  running a Firestore transaction with idempotency keys.
- **Pure domain library in `functions/src/domain`** (no Firebase imports) so economy,
  streak, NPS, scorecard, recommendation and metric maths are unit-tested in isolation
  and reused by the Flutter side through mirrored Dart implementations where needed
  for display.
- **Multi-tenant by construction**: every campus-scoped document carries `campusId`;
  rules and functions check membership per campus.
- **Feature flags** (Remote Config + `feature_configs/{campusId}` + local defaults)
  are separate from **economy config** (`campuses/{id}.economy`, versioned).

See `docs/ARCHITECTURE.md` for diagrams.

## 3. Database changes

Fresh schema — documented in `docs/DATA_MODEL.md`. Deterministic IDs:
`memberships/{campusId_uid}`, `rsvps/{eventId_uid}`, `checkins/{eventId_uid}`,
`event_feedback/{eventId_uid}`, `friendships/{uidA_uidB}` (sorted),
`quest_completions/{questId_uid}`, `coin_ledger/{idempotencyKey}`.

## 4. Migration strategy

No existing data. Seed script (`functions/tools/seed.ts`, `npm run seed`) targets the Emulator Suite only and
refuses to run against a non-emulator project. Production is provisioned by a Super
Admin through `provisionCampus` — never by seed.

## 5. Implementation milestones

| Milestone | Scope | Gate |
|-----------|-------|------|
| A Foundation | plan, scaffold, theme, router, Firebase init, models, auth, roles, campuses, rules baseline, seed infra | `flutter analyze`, functions build |
| B Discovery MVP | onboarding, Tribes, feed, detail, organizer create/edit/cancel, search, RSVP, share, notification foundation | unit + widget tests |
| C Participation | rotating QR, secure/manual check-in, ledger, balances, streaks, feedback, rewards, redemption, referrals, leaderboard, organizer bonus, coin expiry | function tests + rules tests |
| D Intelligence/Social | personalized feed + A/B, social proof, friends/privacy, reviews, organizer analytics v2, Campus Buzz Score | tests |
| E Business | brand quests, brand dashboard, multi-campus provisioning, inter-campus events, ambassador, vendor portal, entitlements, institutional dashboard | tests |
| F Pilot Ops | scorecard, NPS survey, feed/economy health, notification composer, warnings, exports, daily metrics | tests |
| G Hardening | App Check, Crashlytics, rules hardening, indexes, accessibility, CI, docs, deployment | full suite |

## 6. Testing strategy

- `functions/tests/domain/*` — pure logic (economy, streaks, expiry FIFO, NPS, scorecard bands, recommendation scoring, metrics).
- `functions/tests/integration/*` — callable handlers against the Firestore emulator (idempotency, duplicate check-in, QR expiry, redemption race, referral duplicate).
- `functions/tests/rules/*` — `@firebase/rules-unit-testing` negative/positive cases.
- `test/` — Flutter unit, provider and widget tests with `fake_cloud_firestore` / `firebase_auth_mocks`.
- `integration_test/` — student / organizer / admin / brand journeys against the emulator.
- CI: `.github/workflows/ci.yml` runs analyze, flutter test, functions lint/test/build, rules tests. No production secrets required.

## 7. Deployment requirements

See `docs/DEPLOYMENT.md`. Summary: three Firebase projects (dev/staging/prod) selected
via `--dart-define=CB_ENV=...` and `.firebaserc` aliases; `flutterfire configure` per
project; secrets (`QR_SIGNING_SECRET`, optional `POSTHOG_KEY`, FCM/APNs keys) via
`firebase functions:secrets:set`; App Check providers registered per platform.

## 8. Decisions log (ambiguities resolved)

| Topic | Decision |
|-------|----------|
| Streak week | ISO week in campus timezone; a week counts if ≥1 verified check-in. |
| Streak multiplier | Applies to check-in reward only, from streak ≥ threshold (default 3). |
| Coin expiry | Ledger credits carry `expiresAt`; scheduled job writes `expiry` debit entries per credit (FIFO consumption of debits against oldest credits is computed at expiry time). |
| Check-in window | Opens 30 min before start (configurable), closes 2 h after end unless organizer closes earlier. |
| RSVP reward | Granted once per `(event,user)` via ledger key `rsvp:eventId:uid`; re-RSVP after cancel does not re-award. |
| QR token | HMAC-SHA256 signed JSON `{e,c,w,n,v}` issued server-side; window 30 s + 15 s grace. |
| Organizer identity | Organizer is a `memberships` role (`organizer`) linked to a student user; clubs own events. |
| Vendor login | Firebase Auth email account with `memberships` role `vendor` scoped to a `vendorId`. |
| Brand data | Brands only ever read `quests/{id}.stats` aggregates; min group size 5 for Tribe/campus breakdowns. |
| Recommendation | Server function `getRecommendedFeed` returns ranked ids + reason codes; client falls back to chronological query on any failure. |
| Deep links | `app_links` package; `https://campusbuzz.app/e/{eventId}` + custom scheme `campusbuzz://`. |
| Payments | Entitlements + `BillingAdapter` seam (`functions/src/lib/billing.ts`, manual adapter) only; no gateway. |

## 9. Milestone log

_(appended as each milestone completes)_

### Milestone A — Foundation (done)
Repo scaffolded from empty (Flutter 3.47 / Dart 3.13, Node 22 functions). Firebase
config (`firebase.json`, `.firebaserc`, emulator ports), default-deny Firestore +
Storage rules, 60+ composite indexes, Remote Config template, `.env.example`.
Functions: config (collections, defaults, secrets), pure domain layer, lib layer
(auth/roles, ledger, notifications, audit, analytics), all handlers, deterministic
emulator seed (`npm run seed`). Flutter: bootstrap with emulator wiring, App Check,
Crashlytics, Remote Config defaults; dark Material 3 theme (Syne/DM Sans, orange/lime);
models; auth/role/flag providers; GoRouter with auth-phase redirects; shells.

### Milestone B — Discovery MVP (done)
Welcome/sign-in/register (campus domain resolution)/verify/forgot; onboarding
(name → ≥3 Tribes with primary → prefs + consent → `completeOnboarding`); home feed
(greeting, coin/streak strip, Tribe quick filter, social proof, ranked or chronological);
explore/search (tokens, today/tomorrow/week/custom, Tribe, organizer); event detail
(map deep link, share link, capacity/waitlist, RSVP one-tap with +5 once, reviews);
organizer create/edit/cancel/close with poster upload; reminders (24h/1h) scheduled
server-side; push token registration; deep links (`/e/{id}`, `/r/{code}`, `/q/{id}`).

### Milestone C — Participation engine (done)
`startEventCheckin` / `issueEventQrToken` (HMAC, 30 s rotation, 15 s grace, session
nonce) / `checkInWithQr` / `manualCheckIn` (audited) / `searchAttendees`; scan screen
with permission fallback and result sheet; immutable ledger + balances + FIFO expiry
+ reconciliation; streaks in campus tz with 2× from week 3; feedback (+10, verified
only); rewards store, transactional redemption with code + QR, redemption detail,
wallet/ledger; referrals (+25 on first attendance, once); Tribe leaderboard (weekly,
check-ins only); organizer bonus (+50, ≥10 attendees, once); certificates (PDF).

### Milestone D — Intelligence & social (done)
`getRecommendedFeed` (weighted, reason codes, deterministic A/B, chronological
fallback); social proof from `tribeRsvps`; friends (request/accept/decline/unfriend/
block) with opt-in activity visibility enforced in rules; anonymous reviews +
moderation + reporting; organizer analytics v1 (funnel, conversion) and v2 (Tribe
breakdown, trends, repeat rate, best categories, day/time, premium acquisition
sources); Campus Buzz Score with visible components.

### Milestone E — Business platform (done)
Brand quests (draft → submitted → approved/live → paused/completed/cancelled;
attendance / QR activation / event-count / checklist / streak types; completion on
verified check-in; aggregate analytics with min-group suppression; financial status
metadata); brand dashboard + quest form; campus provisioning, brand accounts,
entitlements (organizer_premium, campus_analytics, brand_dashboard) in the Platform
workspace; inter-campus events (`participatingCampusIds`, flag-gated); ambassador
dashboard (link, weekly target, verified referrals, incentives, badges, toolkit);
vendor portal (validate/fulfil, settlement by month) + admin settlement/refunds;
institutional analytics (entitlement-gated) with CSV exports.

### Milestone F — Pilot operations (done)
`getCampusDashboard` (WAP count/%, organizers, supply, conversion, redemption both
ways, retention both definitions, NPS, economy health with thresholds, QR failure
rate, warnings); pilot scorecard with configurable RYG bands + weekly snapshots;
surveys/NPS/"would miss"; feed-health flags; notification composer (audience, Tribes,
event RSVPs, inactive; dry-run audience size; cap-aware delivery); event review queue,
users/suspension, organizers & roles, rewards/vendors, fraud review, configuration
(domains, timezone, flags, versioned economy with announce), audit log; daily
aggregation + leaderboard refresh + maintenance sweeps.

### Milestone G — Hardening (done in this build; see KNOWN_LIMITATIONS)
Rules tests (22), callable integration tests (22), domain tests (47), Flutter unit +
widget tests, `flutter analyze` clean of errors, CI workflow, App Check + Crashlytics
wiring, accessibility (semantics, band icons, contrast test, touch targets, text
scaling clamp), offline persistence, docs set, Makefile, dev script, web build.
