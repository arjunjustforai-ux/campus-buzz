# CampusBuzz — Test Plan

## Automated

| Layer | Location | Runner | What it proves |
|---|---|---|---|
| Domain unit (pure TS) | `functions/tests/domain/*.test.ts` | `npm test` (vitest) | earning rules, streak maths in campus tz, FIFO expiry, economy health, QR sign/verify/rotation/grace/tamper, WAP/conversion/redemption/NPS/retention/supply formulas, scorecard bands (never green without data), Campus Buzz Score, recommendation ranking + A/B assignment, search tokens, codes |
| Callable integration (emulator) | `functions/tests/integration/*.test.ts` | `npm run test:integration` | RSVP idempotency + capacity/waitlist promotion + cancelled/other-campus rejection; QR check-in +20 once, duplicate scan idempotent, expired/forged/stale-session/not-started tokens, organizer-only issuance, manual check-in audit/idempotency, streak 2× from week 3, referral paid once; feedback requires check-in (+10 once), event closure organizer bonus once; redemption insufficient coins w/ shortfall, **three concurrent redemptions of one unit → exactly one succeeds**, vendor validate/fulfil scope, refund once, admin adjustments audited, students cannot create rewards/adjust coins; ledger FIFO + expiry of unspent remainder only (idempotent); roles cannot be self-granted, suspension blocks participation, brand quest lifecycle → student completion on check-in → aggregate analytics with small-group suppression |
| Security rules | `functions/tests/rules/firestore.rules.test.ts` | `npm run test:rules` | student cannot change balance / create ledger / elevate role / write check-in, RSVP, review; safe profile fields only; admin cannot write memberships or inventory directly; cross-campus isolation for events, metrics, audit; friend visibility opt-in; brand cannot read completions/balances or others' quests; vendor scope; analytics_events own uid create-only; support requests; unauthenticated denied |
| Flutter unit | `test/core/*` | `flutter test` | model parsing, economy defaults, timezone rendering, day labels, error copy mapping |
| Flutter widget | `test/widgets/*`, `test/features/*` | `flutter test` | state views, band pills (no colour-only status), stat tiles, chip semantics, touch targets, contrast of status colours, reason-code copy |
| Static | `flutter analyze`, `npm run lint`, `tsc` | CI | no errors |
| CI | `.github/workflows/ci.yml` | GitHub Actions on PR | all of the above, no production secrets |

Run everything: `make test` (see Makefile) or the commands in `README.md`.

## Integration journeys (`integration_test/`)

`integration_test/journeys_test.dart` drives the real app against the seeded
emulator (`flutter test integration_test -d chrome --dart-define=USE_EMULATORS=true`
or on a device). Journeys:

- **Student**: sign in → feed → RSVP (+5) → scan token → verified (+20) → feedback (+10) → redeem → code.
- **Organizer**: sign in → create event → publish → RSVP list → start QR → manual fallback → close → analytics.
- **Admin**: approve organizer → manage reward → pilot metrics → review event → audit log.
- **Brand**: quest draft → submit → admin approves → student participates → metrics.

## Manual QA checklist (failure cases)

bad internet · no camera permission · denied notifications · expired QR · malformed
QR · duplicate QR · event cancelled after RSVP · capacity reached (waitlist on/off) ·
reward out of stock · insufficient coins · simultaneous redemption · image upload
failure · email not from approved campus · unverified email · organizer not approved
· user suspended · role removed mid-session · push unavailable (web/emulator) · empty
analytics period · deleted event organizer · account deletion · second campus /
inter-campus event · text scaling 1.4× · keyboard navigation on dashboards.

## Results (2026-09-03, this build)

- functions domain: 47/47 passed
- functions integration + rules (emulator): 44/44 passed
- flutter analyze: 0 errors (lint infos only)
- flutter test: all passed
- integration journeys: written; require a Chrome/device session with the emulator (not executed in the headless build container).
