# CampusBuzz — QR Check-in

Verified physical participation is the product's core differentiator. The QR image
is only a transport for a short-lived signed token; all validation is server-side.

## Organizer flow

1. From `checkinOpensAt` (default 30 min before start) the organizer opens **Live
   mode** and taps *Start check-in* → `startEventCheckin` creates
   `event_qr_sessions/{eventId}` with a fresh random `nonce` and sets
   `events.checkinActive = true`.
2. The live screen calls `issueEventQrToken` every rotation. The function returns
   `base64url(payload).base64url(HMAC-SHA256(payload, QR_SIGNING_SECRET))` where
   payload = `{e: eventId, c: campusId, w: floor(now/30s), n: nonce, v: 1}`.
3. The screen shows a giant QR, live check-in/RSVP/capacity counts, a QR health
   indicator (refresh failures) and the manual check-in panel.
4. *Stop check-in* deactivates the session; `closeEndedEvents` also stops it when
   the window closes.

## Student flow

1. **Scan** tab → `mobile_scanner` reads the QR (torch/camera switch, permission
   fallback copy). Web/emulator builds also accept a pasted token.
2. `checkInWithQr(token)` verifies: signature (timing-safe), token version, window
   validity (own window + 15 s grace; future windows rejected), session active and
   nonce matches, user active + campus member (incl. inter-campus), event not
   cancelled, check-in window open, `qr_checkin_enabled` flag.
3. `recordCheckin` transaction: create `checkins/{eventId_uid}` (idempotent),
   increment event/tribe counters, award coins once (`checkin:{eventId}:{uid}`,
   streak multiplier applied), update `participation_stats` (streak, tags,
   weekday/hour affinities), pay the referrer once if this is the referred
   student's first attendance, then evaluate joined quests.
4. Result sheet: "You're checked in. +20 BuzzCoins." with streak context; failures
   show product copy (expired → "Ask the organizer to refresh the QR").

## Manual fallback

`manualCheckIn(eventId, uid, reason)` — organizer/campus admin only, attendee must
be a member of a participating campus, allowed until `checkinClosesAt +
manualCorrectionWindowHours` (48h). Records `method: manual`, `byUid`, `reason`,
writes an `audit_logs` entry (`checkin.manual`), and uses the same transaction, so
it can never double-award or duplicate a QR check-in. `searchAttendees` provides the
attendee lookup (RSVP'd first).

## Fraud prevention summary

signed short-lived tokens · 30 s rotation + 15 s grace · per-session nonce · one
check-in per (event,user) by id · server timestamps · check-in window · organizer-
only issuance · manual check-in audit · scan failure counters → fraud dashboard.

## Failure cases handled

expired QR · malformed QR · forged signature · stale session (organizer restarted) ·
check-in not started · window closed · cancelled event · suspended user · other
campus · duplicate scan (returns `alreadyCheckedIn`, 0 coins) · no camera permission
(explains manual fallback) · offline (retry copy).
