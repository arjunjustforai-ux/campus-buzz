import 'package:campusbuzz/core/models/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  test('Event.fromDoc maps fields, stats and derived flags', () async {
    final start = DateTime.utc(2026, 9, 10, 12);
    await db.collection('events').doc('e1').set({
      'campusId': 'c1', 'participatingCampusIds': ['c1', 'c2'], 'clubId': 'club', 'clubName': 'Finance Club', 'organizerUid': 'o', 'title': 'Finance Fest', 'description': 'd',
      'startAt': Timestamp.fromDate(start), 'endAt': Timestamp.fromDate(start.add(const Duration(hours: 2))), 'location': {'name': 'Hall', 'address': 'A', 'lat': 12.9, 'lng': 77.6},
      'capacity': 10, 'waitlistEnabled': true, 'tribeIds': ['t1'], 'tags': ['fin'], 'status': 'published', 'stats': {'rsvpCount': 10, 'checkinCount': 4, 'ratingAvg': 4.5, 'ratingDist': {'5': 2}}, 'tribeRsvps': {'t1': 7},
    });
    final e = Event.fromDoc(await db.collection('events').doc('e1').get());
    expect(e.title, 'Finance Fest');
    expect(e.isFull, isTrue);
    expect(e.isCrossCampus, isTrue);
    expect(e.spotsLeft, 0);
    expect(e.stats.conversion, 40);
    expect(e.location.lat, 12.9);
    expect(e.tribeRsvps['t1'], 7);
    expect(e.startAt.isUtc, isTrue);
  });

  test('Membership parses roles and ignores unknown ones', () async {
    await db.collection('memberships').doc('c1_u1').set({'campusId': 'c1', 'uid': 'u1', 'roles': ['student', 'organizer', 'wizard'], 'status': 'active', 'clubIds': ['x']});
    final m = Membership.fromDoc(await db.collection('memberships').doc('c1_u1').get());
    expect(m.roles, {Role.student, Role.organizer});
    expect(m.has(Role.campusAdmin), isFalse);
    expect(Role.campusAdmin.wire, 'campus_admin');
    expect(Role.parse('super_admin'), Role.superAdmin);
  });

  test('EconomyConfig falls back to documented defaults', () {
    final e = EconomyConfig.fromJson(null);
    expect(e.rsvpReward, 5);
    expect(e.checkinReward, 20);
    expect(e.feedbackReward, 10);
    expect(e.referralReward, 25);
    expect(e.organizerReward, 50);
    expect(e.streakThresholdWeeks, 3);
    expect(e.streakMultiplier, 2);
    expect(e.coinExpiryDays, 90);
    final custom = EconomyConfig.fromJson({'checkinReward': 30, 'version': 4});
    expect(custom.checkinReward, 30);
    expect(custom.version, 4);
    expect(custom.rsvpReward, 5);
  });

  test('LedgerEntry labels are human copy', () async {
    await db.collection('coin_ledger').doc('k').set({'type': 'credit', 'reason': 'checkin', 'amount': 40, 'createdAt': Timestamp.now(), 'meta': {'multiplierApplied': true}});
    final l = LedgerEntry.fromDoc(await db.collection('coin_ledger').doc('k').get());
    expect(l.label, contains('2x'));
    expect(l.amount, 40);
  });

  test('Reward sold-out and type labels', () async {
    await db.collection('rewards').doc('r').set({'campusId': 'c1', 'title': 'Voucher', 'description': '', 'type': 'printing_credit', 'coinCost': 80, 'inventory': 0});
    final r = Reward.fromDoc(await db.collection('rewards').doc('r').get());
    expect(r.soldOut, isTrue);
    expect(r.typeLabel, 'Printing');
  });

  test('Entitlement isActive respects validUntil', () async {
    await db.collection('entitlements').doc('a').set({'key': 'organizer_premium', 'status': 'active', 'validUntil': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)))});
    await db.collection('entitlements').doc('b').set({'key': 'organizer_premium', 'status': 'active', 'validUntil': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)))});
    expect(Entitlement.fromDoc(await db.collection('entitlements').doc('a').get()).isActive, isTrue);
    expect(Entitlement.fromDoc(await db.collection('entitlements').doc('b').get()).isActive, isFalse);
  });
}
