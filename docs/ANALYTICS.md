# CampusBuzz — Analytics & Core Metrics

## Instrumentation

Client `Analytics.track(event, props)` fans out to: first-party
`analytics_events` (Firestore, own uid, ≤14 keys), Firebase Analytics (non-emulator)
and PostHog when `POSTHOG_KEY` is set. Server-side `track()` writes the same
collection and optionally forwards to PostHog (`POSTHOG_SERVER_KEY`). Authoritative
metrics never depend on a vendor — they are computed from Firestore records.

Shared properties: `uid`, `campusId`, `eventId`, `organizerId` (club), `tribeIds`,
`source`/`screen`, `feedVariant`, `role`. No emails, names or free text.

Events emitted: `app_open registration_started registration_completed
email_verified onboarding_started onboarding_completed tribe_selected feed_viewed
event_impression event_opened search_performed search_result_opened rsvp_created
rsvp_cancelled qr_scan_started checkin_success checkin_failure manual_checkin
feedback_prompted feedback_submitted coins_earned coins_expired reward_viewed
reward_redeemed redemption_fulfilled referral_shared referral_signup
referral_first_attendance friend_request_sent friend_request_accepted
organizer_event_created organizer_event_published organizer_event_cancelled
organizer_qr_started quest_viewed quest_joined quest_completed notification_sent
notification_opened`.

## Core metric definitions (`functions/src/domain/metrics.ts`, unit-tested)

| Metric | Formula |
|---|---|
| **WAP** (North Star) | unique users with ≥1 verified check-in in the ISO week (campus tz) — reported as count **and** % of active campus memberships |
| RSVP → attendance | verified check-ins ÷ RSVPs (per event, and across events in a window) |
| Discovery conversion | RSVPs ÷ unique event opens (also impressions → opens → RSVP) |
| Redemption rate | coins redeemed ÷ coins earned **and** users redeemed ÷ users earned (both labelled) |
| NPS | %promoters (9–10) − %detractors (0–6); passives 7–8 |
| "Would miss CampusBuzz" | % answering yes / strongly yes |
| Week-6 retention | Week-1 cohort (first cohort week of the campus) with (a) any RSVP/check-in in week 6 = product retention, (b) verified check-in in week 6 = participation retention |
| Organizer supply health | organizers posting this week, events posted this week, events next 7 days, events today/tomorrow vs targets → flags `no_upcoming_events`, `empty_feed_risk`, `below_weekly_event_target` |
| Repeat attendee rate | attendees with ≥2 verified events ÷ attendees |

## Aggregation

- `metrics_daily/{campusId_date}` — nightly (`aggregateDailyCampusMetrics`) and on
  demand (`runMetricsAggregation`): registered, active users, WAP, events, RSVPs,
  check-ins, coins earned/redeemed/expired, active organizers, quest completions.
- `pilot_metrics/{campusId_weekKey}` — weekly scorecard snapshot with bands.
- `tribe_leaderboards` — every 30 min from real check-ins (never likes/views).
- `getCampusDashboard` — live computation with bounded queries and `count()`
  aggregations; feeds the Campus Ops dashboard, scorecard, economy health, warnings.
- `getOrganizerEventAnalytics` / `getClubAnalytics` — organizer v1/v2.
- `getInstitutionalAnalytics` — student-affairs view (entitlement-gated).
- `getBrandQuestAnalytics` — aggregates only; groups < 5 suppressed.

## Pilot scorecard bands (defaults; configurable in `campuses.pilot.bands`)

| Metric | Red | Yellow | Green |
|---|---|---|---|
| Registered students | < 75 | 75–149 | ≥ 150 |
| WAP % | < 15 | 15–29.99 | ≥ 30 |
| Week-6 participation retention | < 25 | 25–44.99 | ≥ 45 |
| Organizers posting weekly | < 5 | 5–9 | ≥ 10 |
| RSVP → attendance | < 25 | 25–39.99 | ≥ 40 |
| NPS | < 20 | 20–39 | ≥ 40 |
| Would miss CampusBuzz | < 20 | 20–49.99 | ≥ 50 |

`no_data` is a fourth band — a metric is never green without real data. Targets
are displayed separately and labelled as targets.

## Campus Buzz Score (feature-flagged)

`score = 100 × Σ w_i · n_i`, with defaults `w = {wap 0.4, rsvpToAttendance 0.2,
eventSupply 0.2, retention 0.2}` and normalisations `n_wap = min(1, WAP%/50)`,
`n_conv = conv%/100`, `n_supply = min(1, eventsThisWeek / weeklyEventsTarget)`,
`n_ret = retention%/100`. Components are shown beside the score. It is an explicit,
configurable weighted score — not an accreditation metric.

## Recommendation engine (rules-based, explainable)

`rankEvents` scores each upcoming event with configurable weights
(`feature_configs.recommendationWeights`, defaults tribeAffinity 3, categoryAffinity
2, friendAttendance 1.5, preferredDayTime 1, urgency 1.5, popularity 1) and emits
reason codes `because_of_tribe · similar_to_attended · friends_attending ·
popular_on_campus · happening_soon`. Users are deterministically assigned
`chronological` / `personalized` (`feedVariantFor(uid)`), stored on the profile and
attached to `feed_viewed`, `event_opened`, `rsvp_created` for A/B measurement. The
client always falls back to the chronological Firestore query.
