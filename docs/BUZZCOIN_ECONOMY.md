# CampusBuzz — BuzzCoin Economy

BuzzCoins are a closed-loop participation incentive. They have no cash value,
cannot be withdrawn, are not a cryptocurrency, and exist only to turn verified
participation into tangible campus value.

## Earning rules (defaults, per-campus configurable in `campuses.economy`)

| Action | Ledger key | Default |
|---|---|---|
| RSVP (once per event/user) | `rsvp:{eventId}:{uid}` | +5 |
| Verified check-in (QR or audited manual) | `checkin:{eventId}:{uid}` | +20 (×2 with streak multiplier) |
| Post-event feedback (verified attendees only) | `feedback:{eventId}:{uid}` | +10 |
| Referred friend's first verified attendance (to referrer) | `referral:{referredUid}` | +25 |
| Organizer runs an event with ≥10 verified attendees | `organizer:{eventId}` | +50 |
| Brand quest completion | `quest:{questId}:{uid}` | quest-defined |
| Admin adjustment (reason required, audited) | `adjustment:{id}` | ± |
| Redemption refund (admin) | `refund:{redemptionId}` | + cost |

Cancelling and re-RSVPing never re-awards (the ledger key already exists).

## Streaks

A participation week is an ISO week (Mon–Sun) in the **campus timezone** with at
least one verified check-in. `updateStreak`:

- first participation → streak 1
- consecutive week → +1
- same week → unchanged
- gap of one or more full weeks → reset to 1

From `streakThresholdWeeks` (default 3) the check-in reward is multiplied by
`streakMultiplier` (default 2). The check-in that completes week 3 is already paid
at 2×. `effectiveStreak` (shown in the app) reports 0 once a full week is missed.

## Expiry (default 90 days, configurable; 0 disables)

Every credit carries `expiresAt = createdAt + coinExpiryDays` and a `remaining`
portion. Debits (redemptions/adjustments) are matched **FIFO** against the oldest
un-expired credits (`applyLedgerFifo`, hourly), decrementing `remaining`. The nightly
`expireBuzzCoins` job writes an `expiry:{creditKey}` entry for the unspent
`remaining` of each credit whose `expiresAt` has passed, marks the credit expired,
and reduces the balance. Historical entries are never rewritten. `expiringSoon` on
the balance doc powers the "N coins expire on …" warning in the app.

## Integrity

```
balance = Σ credits − Σ debits − Σ expirations   (all in coin_ledger for the uid)
```

`coin_balances` is a materialised cache updated in the same transaction as each
ledger write; `reconcileCoinBalance` recomputes from the ledger and audits drift.
Ledger doc ids are idempotency keys, so Cloud Function retries cannot double-award.
Redemption checks balance and inventory inside one transaction (tested with three
concurrent redemptions of a one-unit reward: exactly one succeeds).

## Economy health (Campus Ops dashboard)

| Metric | Healthy | Warning |
|---|---|---|
| Average weekly earn per active user | 30–60 | > 80 |
| Redemption rate (coins redeemed ÷ coins earned, 30d) | 25–45% | < 15% |
| Coins earned (30d) ÷ redeemable inventory (coins) | ≤ 3× | > 3× |

Also reported: coins earned/redeemed this month, outstanding balance, users who
redeemed ÷ users who earned, redeemable inventory face value, coins in circulation.
Warnings are decision support — the system never changes the economy on its own.

## Versioning and notice

`updateCampusConfig` bumps `economy.version` on any rule change, snapshots the
previous and next config to `economy_versions/{campusId}_v{n}` with the actor and
an `effectiveAt`/description, and can enqueue a transactional in-app notice to all
members (`announce: true`). Ledger entries record the `economyVersion` they were
created under.

## Reward store defaults (seed / demo)

₹50 canteen voucher 100 · priority registration 75 · 50 pages printing 80 ·
merchandise 200–500 · participation certificate free after verified check-in.
Production inventory and pricing are admin-configurable (`upsertReward`, audited).
