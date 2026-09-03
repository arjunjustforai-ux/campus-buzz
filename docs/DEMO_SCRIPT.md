# CampusBuzz — Demo Script (emulator, ~12 minutes)

Setup once: `make setup && make emulators` (terminal 1), `make seed` (terminal 2),
then `make run-web` (Chrome). Emulator UI at http://localhost:4000.
All accounts use password `CampusBuzz!123` and are **emulator-only, synthetic**.

| Role | Email |
|---|---|
| Student | student@demo.campusbuzz.test |
| Organizer (Finance & Investment Club, E-Cell) | organizer@demo.campusbuzz.test |
| Ambassador | ambassador@demo.campusbuzz.test |
| Campus Ops | admin@demo.campusbuzz.test |
| Brand (FitFuel) | brand@demo.campusbuzz.test |
| Vendor (Main Canteen) | vendor@demo.campusbuzz.test |
| Super admin | superadmin@demo.campusbuzz.test |

Tip: the sign-in screen shows one-tap chips for these accounts when `USE_EMULATORS=true`.

## Student (Priya)

1. Sign in as **student** → dark CampusBuzz feed, greeting, BuzzCoin + streak strip, 14 upcoming events, "12 Finance Geeks are going" social proof.
2. Tap the **Finance Geeks** chip → Tribe-filtered feed.
3. Open **Finance Fest: Mock Trading Floor** → RSVP → "You're in. +5 BuzzCoins." (already RSVP'd by seed? then use *Build Night*).
4. Tap the BuzzCoins tile → ledger shows the RSVP credit with its expiry date.

## Organizer (Rohan) — second browser/profile

5. Sign in as **organizer** → Organizer workspace → Events → open the event you RSVP'd to → **Live mode** → *Start check-in* (event must be within 30 min of start; for the demo pick **Finance Fest**, seeded ~26h out — instead open **Weekend Futsal Friendly**? That's past. Easiest: create a new event starting in 10 minutes: *Create event* → title "Demo check-in", club Finance & Investment Club, start = now+10 min, Tribe Finance Geeks → Publish).
6. On Live mode, *Copy token* (web) — the giant QR rotates every 30 s with a health indicator.

## Student again

7. Scan tab → paste the token (web/dev) or scan the QR on a phone → "You're checked in. +20 BuzzCoins." (streak week 1).
8. Event detail now shows "Checked in" + Certificate; tap **Rate this event** → 5 stars → "+10 BuzzCoins."
9. Rewards → **₹50 Canteen Voucher** (100 coins; Priya has plenty from seed history) → Redeem → code + QR.

## Vendor

10. Sign in as **vendor** → Partner workspace → paste the code → Validate → Mark fulfilled. Settlement tab shows the month total.

## Organizer analytics

11. Organizer → Analytics on **Valuation Masterclass** (past, seeded): impressions → opens → RSVPs → check-ins, RSVP→attendance conversion, Tribe breakdown, rating distribution, review themes.
12. Club analytics: attendance trend, best categories, weekday pattern, premium acquisition sources (Finance Club has `organizer_premium`).

## Campus Ops

13. Sign in as **admin** → Dashboard: WAP count and %, active organizers, RSVP→attendance, redemption rate (both definitions), economy health with thresholds, feed-health warnings, Campus Buzz Score with components.
14. **Pilot scorecard**: seven RYG rows with thresholds and "no data" where data is missing (week-6 retention needs 6 weeks).
15. **Event review**: the flagged *Open Mic* (a student reported the venue) → Approve/Flag/Unpublish. **Organizers & roles**: approve the pending Photography Club request. **Audit log**: every action above is there.
16. **Notifications**: audience "Tribes → Sports Heads" → Validate audience → send (cap enforced per student).

## Brand

17. Sign in as **brand** → **FitFuel Fitness Week** (live): eligible audience, joins, verified completions, completion %, repeat participation, cost per verified action, Tribe breakdown with small groups suppressed, timeline.
18. **FitFuel Productivity Challenge** is *submitted* → as admin, Brand quests → Approve → as student, Quests → join → checklist.

## Platform

19. Sign in as **superadmin** → Campuses (JAGSoM + Northgate demo), provision a third, Brands, Entitlements. The inter-campus hack event is visible from both campuses.

## Security smoke (Emulator UI → Firestore)

As the student, try to write `coin_balances/demo-student.balance` from the app's
console (`firebase.firestore().doc(...).update(...)`) → permission denied. The rules
tests in `functions/tests/rules` automate this.
