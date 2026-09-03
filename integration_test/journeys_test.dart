// End-to-end journeys against the seeded Firebase Emulator Suite.
//
//   make emulators && make seed
//   flutter test integration_test/journeys_test.dart -d chrome \
//     --dart-define=USE_EMULATORS=true --dart-define=CB_ENV=development
//
// The journeys use the callable layer directly where UI automation would be
// brittle (camera), and the UI for the rest. Demo accounts are emulator-only.
import 'package:campusbuzz/app/app.dart';
import 'package:campusbuzz/app/bootstrap.dart';
import 'package:campusbuzz/core/network/functions_client.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _pw = 'CampusBuzz!123';
const _domain = 'demo.campusbuzz.test';

Future<void> _signIn(String account) async {
  await FirebaseAuth.instance.signOut();
  await FirebaseAuth.instance.signInWithEmailAndPassword(email: '$account@$_domain', password: _pw);
}

CbFunctions _fx() => CbFunctions(FirebaseFunctions.instanceFor(region: 'asia-south1'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(bootstrap);

  testWidgets('student journey: feed → RSVP → check-in → feedback → redeem', (t) async {
    await _signIn('organizer');
    final fx = _fx();
    // Organizer creates an event that starts in 5 minutes and opens check-in.
    final start = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final created = await fx.call('createEvent', {'campusId': 'jagsom-demo', 'clubId': 'finance-club', 'title': 'Integration check-in', 'description': 'e2e', 'startAt': start.toIso8601String(), 'endAt': start.add(const Duration(hours: 1)).toIso8601String(), 'location': {'name': 'Lab'}, 'capacity': 50, 'tribeIds': ['finance-geeks'], 'publish': true});
    final eventId = created['eventId'] as String;
    await fx.call('startEventCheckin', {'eventId': eventId});
    final token = (await fx.call('issueEventQrToken', {'eventId': eventId}))['token'] as String;

    await _signIn('student');
    await t.pumpWidget(const ProviderScope(child: CampusBuzzApp()));
    await t.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('CampusBuzz'), findsWidgets);
    expect(find.textContaining("What's happening"), findsOneWidget);

    final rsvp = await fx.call('createRsvp', {'eventId': eventId, 'source': 'integration'});
    expect(rsvp['status'], 'confirmed');
    expect(rsvp['coinsAwarded'], 5);
    final again = await fx.call('cancelRsvp', {'eventId': eventId});
    expect(again['ok'], true);
    final re = await fx.call('createRsvp', {'eventId': eventId});
    expect(re['coinsAwarded'], 0, reason: 'RSVP coins are earned exactly once');

    final checkin = await fx.call('checkInWithQr', {'token': token});
    expect(checkin['coins'], anyOf(20, 40));
    expect(checkin['alreadyCheckedIn'], false);
    final dup = await fx.call('checkInWithQr', {'token': token});
    expect(dup['alreadyCheckedIn'], true);

    final fb = await fx.call('submitEventFeedback', {'eventId': eventId, 'rating': 5, 'review': 'e2e'});
    expect(fb['coinsAwarded'], 10);

    final red = await fx.call('redeemReward', {'rewardId': 'rw-canteen-50'});
    expect(red['code'], matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));

    // UI: rewards tab shows the redemption.
    await t.tap(find.text('Rewards'));
    await t.pumpAndSettle(const Duration(seconds: 2));
    await t.tap(find.text('My redemptions'));
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text(red['code'] as String), findsWidgets);
  });

  testWidgets('organizer + admin + brand + vendor journeys', (t) async {
    final fx = _fx();
    await _signIn('admin');
    final reward = await fx.call('upsertReward', {'campusId': 'jagsom-demo', 'title': 'E2E reward', 'type': 'voucher', 'coinCost': 1, 'inventory': 3, 'faceValue': 10, 'vendorId': 'canteen'});
    expect(reward['rewardId'], isNotEmpty);
    final dash = await fx.call('getCampusDashboard', {'campusId': 'jagsom-demo'});
    expect(dash['registered'], greaterThan(100));
    expect((dash['scorecard'] as List).length, 7);

    await _signIn('brand');
    final now = DateTime.now().toUtc();
    final q = await fx.call('saveQuestDraft', {'brandId': 'fitfuel', 'title': 'E2E quest', 'description': 'd', 'type': 'event_attendance', 'campusIds': ['jagsom-demo'], 'startAt': now.subtract(const Duration(minutes: 1)).toIso8601String(), 'endAt': now.add(const Duration(days: 1)).toIso8601String(), 'rewardCoins': 5, 'campaignValue': 100});
    await fx.call('submitBrandQuest', {'questId': q['questId']});
    await _signIn('admin');
    final approved = await fx.call('approveBrandQuest', {'questId': q['questId']});
    expect(approved['status'], 'live');
    await _signIn('student');
    await fx.call('joinQuest', {'questId': q['questId']});

    await _signIn('vendor');
    final v = await fx.call('validateRedemption', {'code': 'DEMO-1003'});
    expect(v['valid'], isA<bool>());
  });
}
