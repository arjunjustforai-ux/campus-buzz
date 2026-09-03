# CampusBuzz — Roles and Permissions

Roles are per campus (`memberships.roles`), except `super_admin` (`users.superAdmin`)
and brand membership (`brand_memberships`). One person can hold several roles and
switch workspaces from the profile or the rail without signing out.

| Capability | Student | Organizer | Ambassador | Campus admin | Brand | Vendor | Super admin |
|---|---|---|---|---|---|---|---|
| Register / verify college email / onboard / Tribes | ✔ | ✔ | ✔ | ✔ | ✔* | – | ✔ |
| Browse feed, search, event detail, RSVP/cancel, share | ✔ | ✔ | ✔ | ✔ | ✔* | – | ✔ |
| Scan QR, earn coins, streaks, ledger, redeem, certificates | ✔ | ✔ | ✔ | ✔ | ✔* | – | ✔ |
| Feedback (verified attendees), report content, friends, privacy, export/delete | ✔ | ✔ | ✔ | ✔ | ✔* | – | ✔ |
| Referral code/link | ✔ | ✔ | ✔ (+ambassador stats, toolkit, badges) | ✔ | – | – | ✔ |
| Request organizer/ambassador access | ✔ | – | – | – | – | – | – |
| Create/edit/cancel/close events for own clubs, poster upload | – | ✔ | – | ✔ (all clubs) | – | – | ✔ |
| Live QR, manual check-in, attendee lookup, RSVP list | – | ✔ (own club events) | – | ✔ | – | – | ✔ |
| Event & club analytics (v1/v2, premium window via entitlement) | – | ✔ | – | ✔ | – | – | ✔ |
| Campus dashboard, pilot scorecard, feed/economy health, warnings | – | – | – | ✔ | – | – | ✔ |
| Approve roles, manage clubs/Tribes, suspend/reactivate (reason) | – | – | – | ✔ | – | – | ✔ |
| Event review queue (approve/flag/unpublish), moderate reviews | – | – | – | ✔ | – | – | ✔ |
| Rewards catalog/inventory, vendors, refunds, settlements | – | – | – | ✔ | – | – | ✔ |
| QR/fraud review, audit log (own campus) | – | – | – | ✔ | – | – | ✔ (all) |
| Notification composer (cap-validated), surveys/NPS, exports | – | – | – | ✔ | – | – | ✔ |
| Campus config: domains, timezone, flags, economy (versioned) | – | – | – | ✔ | – | – | ✔ |
| Approve brand quests, set quest status | – | – | – | ✔ (own campus) | – | – | ✔ (+financial status) |
| Institutional analytics (needs `campus_analytics` entitlement) | – | – | – | ✔ | – | – | ✔ |
| Create/submit/pause/complete quests, aggregate quest analytics | – | – | – | – | ✔ | – | ✔ |
| Validate/fulfil redemption codes, settlement summary (own vendor) | – | – | – | ✔ | – | ✔ | ✔ |
| Provision campuses, brand accounts, entitlements, super admins | – | – | – | – | – | – | ✔ |

\* Brand users who are also verified students of a campus get the student
experience there; brand workspace access comes only from `brand_memberships`.

## What no client can ever do (enforced by rules + functions)

grant itself roles · alter any balance · create ledger entries · write a check-in,
RSVP or review directly · approve quests · edit reward inventory · read another
campus's private admin data · read private brand/vendor data of others · assign
itself entitlements · read individual quest completions as a brand.

## How access is granted

- Organizer/ambassador: student requests (`requestRole`) → campus admin approves
  (`setMembershipRole`, chooses club) → audited.
- Campus admin: super admin only.
- Vendor: campus admin grants `vendor` with a `vendorId`.
- Brand: super admin creates `brand_accounts` and adds member uids.
- Entitlements (`organizer_premium`, `campus_analytics`, `brand_dashboard`): super
  admin (clubs: campus admin), recorded with plan and billing status — no gateway.
