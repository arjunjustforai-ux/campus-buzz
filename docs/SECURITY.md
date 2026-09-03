# CampusBuzz — Security

## Authentication

- Firebase Auth email + password. Registration requires the email's domain to be on
  the campus allowlist (`resolveCampusForEmail`, admin-controlled in
  `campuses.domains`). Email verification is enforced before any callable except
  `resolveCampusForEmail`, `exportMyData`, `deleteMyAccount` (`requireAuth`).
- `completeOnboarding` is the only path that creates `users/{uid}` and the initial
  `student` membership. Roles are never taken from client input.
- Emulator shortcuts (`CB_EMULATOR_SKIP_EMAIL_VERIFY`, deterministic QR secret,
  demo accounts) are gated on `FUNCTIONS_EMULATOR` / `USE_EMULATORS` and cannot
  activate against a real project.

## Authorisation

- Roles live in `memberships/{campusId_uid}.roles`; `super_admin` is
  `users.superAdmin` and can only be set by another super admin via `setSuperAdmin`.
- `requireMembership(actor, campusId, roles)` gates every campus-scoped callable;
  `canManageEvent` restricts organizers to their clubs' events.
- Self-elevation is impossible: rules deny all client writes to `memberships`, and
  `setMembershipRole` refuses to change the caller's own roles (unless super admin).
- Brand users are authorised via `brand_memberships`; vendors via `memberships.vendorId`.
- The UI hides workspaces the user lacks, but that is cosmetic — every server call
  re-checks. Hidden buttons are never the security boundary.

## Firestore rules (default deny)

`firestore.rules` grants **read** access per collection based on ownership and
campus membership and grants **write** access only to: own `users` safe fields
(never `status`, `superAdmin`, `referralCode`), `analytics_events` (create-only, own
uid), `support_requests` (own create) and admin status updates on
`content_reports`/`support_requests`. Everything else — ledger, balances,
check-ins, RSVPs, events, rewards, memberships, quests, metrics — is
function-only. `tests/rules/firestore.rules.test.ts` covers: student changing
balance, elevating role, writing check-in, cross-campus reads, organizer editing
events directly, brand reading completions/balances, vendor reading other vendors'
redemptions, admin editing inventory directly, unauthenticated access.

## Storage rules

Path-isolated: `avatars/{uid}`, `posters/{campusId}/{clubId}`,
`clubs/{campusId}/{clubId}`, `rewards/{campusId}`, `brands/{brandId}`,
`exports/{uid}` (read-only). Image content types and size caps (2–5 MB) are enforced.

## Cross-campus isolation

Every rule and function check uses the document's `campusId` (or
`participatingCampusIds` for inter-campus events). Campus admins of A cannot read
B's metrics, audit logs, balances, redemptions or events. Super admin is the only
cross-campus principal.

## QR signing

`issueEventQrToken` signs `{e: eventId, c: campusId, w: window, n: sessionNonce, v: 1}`
with HMAC-SHA256 using the `QR_SIGNING_SECRET` Cloud Functions secret. Tokens rotate
every 30 s (window index) with a 15 s grace; future windows are rejected. The session
nonce changes whenever the organizer restarts check-in, so screenshots of old QRs die.
Validation (`checkInWithQr`) is fully server-side and also checks the session is
active, the event window, membership, suspension, and the deterministic check-in id.
The app never holds the secret. Failures are logged (`checkin_failure`) and counted
on the session for the fraud dashboard. See `QR_CHECKIN.md`.

## BuzzCoin integrity

- Append-only `coin_ledger`; the doc id is the idempotency key so retries can't
  double-award. `writeCredit`/`writeDebit`/`writeExpiry` are the only writers, always
  inside the caller's transaction.
- Balance is derived; `reconcileCoinBalance` recomputes from the ledger and audits drift.
- Redemption debits check balance inside the same transaction that decrements
  inventory (tested for concurrent redemptions of a 1-unit reward).
- Admin adjustments need a privileged role and a reason and write both a ledger
  entry and an audit log — balances are never overwritten.
- Coins are not cash, cannot be withdrawn, and expire from the ledger (never by
  rewriting history).

## App Check

`bootstrap.dart` activates Play Integrity (Android), DeviceCheck (iOS) and
reCAPTCHA v3 (web, when `APP_CHECK_WEB_RECAPTCHA_KEY` is set) in non-emulator
builds; debug providers elsewhere. Callables set `enforceAppCheck: true` except in
the emulator (`ENFORCE_APP_CHECK` can be disabled for staging debugging via
`APP_CHECK_ENFORCE=false`).

## Audit logs

`audit_logs` records actor, action, entity, campus, reason, before/after and a
server timestamp for: role grants/revokes, suspension, manual check-ins, reward
create/update (inventory), economy/config changes (with versioning), quest
approval/status, campus provisioning, coin adjustments, reconciliation drift,
refunds, settlements, notification campaigns, exports, privacy actions. Read-only for
campus admins (own campus) and super admins.

## Secrets

No secrets in source. `QR_SIGNING_SECRET` via `firebase functions:secrets:set`;
optional `POSTHOG_SERVER_KEY`. Client-side public config via `--dart-define` from
`.env.json` (see `.env.example`). Real `firebase_options_*.dart` files are git-ignored.

## Abuse mitigation

- Duplicate RSVP/check-in/feedback impossible (ids); RSVP cycling never re-awards.
- Self-referral and duplicate referral rejected; referral only applies within 14
  days of signup; reward only on first verified attendance.
- Engagement notifications capped per user per campus-day.
- Fraud dashboard surfaces heavy manual check-ins, high QR failure rates and unusual
  redemption volume as review signals, never automatic punishment.
- Suspension blocks all participation callables and is reason-required + audited.

## Account deletion & export

`exportMyData` returns JSON (and stores a copy at `exports/{uid}`).
`deleteMyAccount` tombstones the profile (no PII), deletes memberships and
friendships, anonymises reviews, cancels future RSVPs (adjusting counters), cancels
pending notifications, deletes avatar files and the Auth user. Ledger and check-in
rows keep the uid only, so campus aggregates stay correct. Completes immediately.
