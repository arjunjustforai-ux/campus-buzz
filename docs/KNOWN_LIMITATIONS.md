# CampusBuzz — Known Limitations (honest list)

1. **Not run on a real Firebase project yet.** Everything was validated against the
   Emulator Suite in a headless Linux container. Real-device QR scanning, FCM
   delivery, App Check attestation and App/Universal Links need a staging project
   and physical devices (see `DEPLOYMENT.md`). `lib/firebase_options.dart` holds
   emulator placeholders.
2. **Integration journeys are written, not executed here.** `integration_test/`
   needs Chrome/driver or a device with the emulator running; unit, widget, domain,
   callable-integration and rules tests were executed (see `TEST_PLAN.md`).
3. **Push on web** requires a VAPID key and a service worker; the app degrades
   gracefully (in-app inbox still works from `notification_delivery_logs`).
4. **Map preview** uses "Open in Maps" deep links; no embedded map tiles (a Google
   Maps key is optional and unused so far).
5. **Search** is prefix/token based on Firestore (`searchTokens`), with client-side
   full-phrase filtering — fine for campus scale, not for fuzzy search.
6. **Event posters/avatars** are resized client-side (`image_picker` max 1600px,
   quality 82); no server-side thumbnail generation yet.
7. **Recommendation engine** is rules-based and explainable by design; there is no
   ML model and no claim of uplift until the A/B data says so.
8. **Payments**: entitlements and billing status only; no gateway (by spec).
9. **Vendor portal** shares the Flutter web codebase; it is responsive but not a
   separate lightweight site.
10. **Data export** returns JSON inline and via the native share sheet (and a copy
    in private Storage); there is no signed download link UI yet.
11. **Talent profile** exists only as a private opt-in flag (future-safe, by spec).
12. **Week-6 retention** uses the campus's first cohort week; multi-cohort retention
    curves are not yet visualised.
13. **`analytics_events` growth**: client funnel events are append-only; add a TTL
    policy (Firestore TTL on `at`) before large scale.
14. **Lint infos**: `flutter analyze` reports style infos (`use_build_context_synchronously`
    on already-guarded callbacks, brace style) but zero errors/warnings.
15. **Referral fraud signals** (device/IP) are logged as a field placeholder
    (`referrals.signals`) but not yet populated by the client.
