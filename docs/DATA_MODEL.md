# CampusBuzz — Data Model

All timestamps are Firestore `Timestamp`s written by the server (UTC); the client
renders them in the campus timezone. Deterministic ids prevent duplicates by
construction. Collection names are centralised in `functions/src/config/collections.ts`
and `lib/core/constants/collections.dart`.

| Collection | Doc id | Purpose / key fields | Writer |
|---|---|---|---|
| `users` | uid | email, displayName, avatarUrl, activeCampusId, campusIds[], tribeIds[], primaryTribeId, onboardingCompleted, notificationPrefs{transactional,reminders,engagement,postEvent}, privacy{showActivityToFriends,anonymousFeedback,talentProfileOptIn}, status(active/suspended/deleted), suspension{reason,actorUid,at}, referralCode, referredBy, feedVariant, fcmTokens[], superAdmin | completeOnboarding; client may update safe profile fields only |
| `campuses` | slug | name, shortName, domains[], timezone, status, economy{…versioned}, pilot{targets,bands,economyHealth}, featureFlags{}, privacyPolicyUrl, termsUrl | provisionCampus / updateCampusConfig |
| `memberships` | `{campusId}_{uid}` | campusId, uid, roles[], status, clubIds[], requestedRoles[], roleRequests{}, vendorId, brandId, displayName, tribeIds[], joinedAt | completeOnboarding / setMembershipRole / setUserSuspension |
| `tribes` | id | campusId, name, emoji, color, description, order, active | upsertTribe |
| `clubs` | id | campusId, name, description, category, logoUrl, adminUids[], status | upsertClub / setMembershipRole |
| `events` | auto | campusId, participatingCampusIds[], clubId, clubName, organizerUid, title, description, posterUrl, startAt, endAt, location{name,address,lat,lng}, capacity, waitlistEnabled, tribeIds[], tags[], contact, registrationClosesAt, checkinOpensAt, checkinClosesAt, checkinActive, certificateEnabled, status, reviewStatus, stats{rsvpCount,waitlistCount,checkinCount,manualCheckinCount,feedbackCount,ratingSum,ratingAvg,ratingDist}, tribeRsvps{}, tribeCheckins{}, organizerBonusAwarded, cancellation{}, searchTokens[], reportCount | event handlers |
| `event_qr_sessions` | eventId | active, nonce, startedBy, scanFailures, scanSuccesses | start/stopEventCheckin, checkInWithQr |
| `rsvps` | `{eventId}_{uid}` | eventId, uid, campusId, userCampusId, status(confirmed/waitlisted/cancelled), tribeIds[], source, startAt, eventTitle | createRsvp / cancelRsvp |
| `checkins` | `{eventId}_{uid}` | eventId, uid, campusId, method(qr/manual), byUid, reason, tribeIds[], coinsAwarded, streakAtCheckin, multiplierApplied, certificateRef, weekKey, clubId, tags[], at | recordCheckin |
| `event_feedback` | `{eventId}_{uid}` | rating 1–5, review, structured{}, anonymous, displayName(null if anonymous), status(published/removed), moderation | submitEventFeedback / moderateReview |
| `coin_ledger` | idempotency key (`rsvp:{e}:{u}`, `checkin:{e}:{u}`, `feedback:{e}:{u}`, `referral:{referredUid}`, `organizer:{e}`, `quest:{q}:{u}`, `redemption:{id}`, `expiry:{creditKey}`, `adjustment:{id}`, `refund:{id}`) | uid, campusId, type(credit/debit/expiry/adjustment), reason, amount(±), remaining (credits), expiresAt, expired, fifoApplied/consumed (debits), economyVersion, refId, meta | lib/ledger.ts only |
| `coin_balances` | uid | balance, lifetimeEarned, lifetimeRedeemed, lifetimeExpired, expiringSoon, expiringSoonAt, lastReconciledAt | ledger.ts |
| `participation_stats` | uid | streak, lastWeekKey, multiplierActive, totalCheckins, totalRsvps, attendedTags{}, attendedWeekdays{}, attendedHourBuckets{} | recordCheckin / rsvp |
| `rewards` | auto | campusId, vendorId, title, description, type, coinCost, inventory(null=∞), faceValue, imageUrl, terms, redemptionInstructions, perUserLimit, activeFrom/Until, redemptionExpiryDays, status, stats{redeemed,fulfilled} | upsertReward / redeemReward |
| `redemptions` | auto | uid, campusId, rewardId, rewardTitle, vendorId, coinCost, faceValue, code, status(issued/fulfilled/expired/cancelled), issuedAt, expiresAt, fulfilledAt/By, settlementStatus, settlementMonth | redeemReward / fulfillRedemption / refundRedemption / settleVendorMonth |
| `vendors` | id | campusId, name, contact, settlementTerms, status, stats{fulfilled,pendingSettlementValue}, settlements{month:{count,value}} | upsertVendor |
| `referrals` | referredUid | referrerUid, referredUid, campusId, code, ambassador, signupAt, firstAttendanceAt, rewardAwarded, signals{} | applyReferral / recordCheckin |
| `friendships` | sorted `{a}_{b}` | uids[2], requesterUid, status(pending/accepted/blocked), blockedBy | friends handlers |
| `brand_accounts` / `brand_memberships` | id / `{brandId}_{uid}` | name, status, logoUrl / brandId, uid, status | upsertBrandAccount |
| `quests` | auto | brandId, title, description, creativeUrl, campusIds[], tribeIds[], startAt, endAt, type, criteria{eventIds,count,checklist,streakWeeks,tagFilter}, rewardCoins, participantLimit, campaignValue, terms, sponsorDisclosure, status, financialStatus, stats{views,joins,completions,coinsDistributed,campusBreakdown,tribeBreakdown}, approvedBy | quest handlers |
| `quest_completions` | `{questId}_{uid}` | status(joined/completed), progress{eventIds,checklist,count}, coinsAwarded, brandId, tribeIds | joinQuest / completeQuestInternal |
| `notification_jobs` | dedupeKey | uid, campusId, category, title, body, route, scheduledFor, status(pending/processing/sent/skipped/failed/cancelled), attempts | notifications.ts |
| `notification_delivery_logs` | auto | jobId, uid, category, status, reason, dayKey, title, route | processNotificationJobs |
| `surveys` / `survey_responses` | auto / `{surveyId}_{uid}` | title, status, closesAt, stats / answers{love,annoys,wouldMiss,helpedAttend,nps} | createSurvey / submitSurveyResponse |
| `metrics_daily` | `{campusId}_{YYYY-MM-DD}` | registered, activeUsers, wap, wapPercent, events, rsvps, checkins, manualCheckins, coinsEarned/Redeemed/Expired, activeOrganizers, questCompletions | aggregateDailyCampusMetrics |
| `pilot_metrics` | `{campusId}_{weekKey}` | rows[] (scorecard), raw{} | calculatePilotScorecard |
| `tribe_leaderboards` | `{campusId}_{weekKey}` and `{campusId}_current` | rows[{tribeId,name,count,rank,previousRank,movement}] | refreshTribeLeaderboards |
| `feature_configs` | campusId | flags{}, recommendationWeights{} | admin |
| `economy_versions` | `{campusId}_v{n}` | full economy snapshot + previous + changedBy | updateCampusConfig |
| `entitlements` | `{subjectType}:{subjectId}:{key}` | status, plan, billingStatus, validUntil, grantedBy | setEntitlement |
| `audit_logs` | auto | actorUid, action, entityType, entityId, campusId, reason, before, after, at | lib/audit.ts |
| `content_reports` | `{type}:{id}:{reporterUid}` | reason, status | reportContent; admin updates status |
| `support_requests` | auto | uid, campusId, message, status | client create; admin update |
| `analytics_events` | auto | event, uid, campusId, eventId, … | client create (own uid) + server |
| `data_exports` | auto | uid, path, bytes | exportMyData |

## Invariants (enforced by transactions + tests)

- `coin_balances.balance == Σ coin_ledger.amount` for the uid (`reconcileCoinBalance` repairs and audits drift).
- One RSVP / check-in / feedback per `(event, user)` — deterministic ids.
- One coin award per idempotency key — the ledger doc id is the key.
- `rewards.inventory ≥ 0`, `coin_balances.balance ≥ 0` (checked inside the redeem transaction).
- Referral reward at most once per referred uid (`referral:{referredUid}`).
- Organizer bonus at most once per event (`organizer:{eventId}`).

## Indexes

See `firestore.indexes.json` — includes upcoming events by campus/date, Tribe/search
token filters, organizer events, user RSVPs/check-ins, rewards by campus/status,
redemptions by vendor/status/settlement, quests by campus/status, ledger expiry/FIFO
scans, notification job scheduling and metrics/pilot/audit ordering.
