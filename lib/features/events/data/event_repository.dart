import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';

/// Read-side event data (Firestore, rules-scoped, paginated) + write-side via functions.
final tribesProvider = StreamProvider<List<Tribe>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.tribes).where('campusId', isEqualTo: campusId).snapshots().map((s) => (s.docs.map(Tribe.fromDoc).where((t) => t.active).toList())..sort((a, b) => a.order.compareTo(b.order)));
});

final tribeMapProvider = Provider<Map<String, Tribe>>((ref) => {for (final t in ref.watch(tribesProvider).value ?? const <Tribe>[]) t.id: t});

final clubsProvider = StreamProvider<List<Club>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.clubs).where('campusId', isEqualTo: campusId).snapshots().map((s) => (s.docs.map(Club.fromDoc).toList())..sort((a, b) => a.name.compareTo(b.name)));
});

/// Chronological upcoming feed for the active campus (includes inter-campus events we're invited to).
final upcomingEventsProvider = StreamProvider<List<Event>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  final now = Timestamp.fromDate(DateTime.now().toUtc().subtract(const Duration(hours: 3)));
  return ref
      .watch(firestoreProvider)
      .collection(Col.events)
      .where('participatingCampusIds', arrayContains: campusId)
      .where('status', isEqualTo: 'published')
      .where('startAt', isGreaterThanOrEqualTo: now)
      .orderBy('startAt')
      .limit(60)
      .snapshots()
      .map((s) => s.docs.map(Event.fromDoc).toList());
});

final eventProvider = StreamProvider.family<Event?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.events).doc(id).snapshots().map((s) => s.exists ? Event.fromDoc(s) : null));

final myRsvpProvider = StreamProvider.family<Rsvp?, String>((ref, eventId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.rsvps).doc(Ids.rsvp(eventId, uid)).snapshots().map((s) => s.exists ? Rsvp.fromDoc(s) : null);
});

final myCheckinProvider = StreamProvider.family<Checkin?, String>((ref, eventId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.checkins).doc(Ids.checkin(eventId, uid)).snapshots().map((s) => s.exists ? Checkin.fromDoc(s) : null);
});

final myFeedbackProvider = StreamProvider.family<Feedback?, String>((ref, eventId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.eventFeedback).doc(Ids.feedback(eventId, uid)).snapshots().map((s) => s.exists ? Feedback.fromDoc(s) : null);
});

/// Upcoming RSVPs for the current user.
final myUpcomingRsvpsProvider = StreamProvider<List<Rsvp>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.rsvps).where('uid', isEqualTo: uid).where('status', whereIn: ['confirmed', 'waitlisted']).where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().toUtc().subtract(const Duration(hours: 3)))).orderBy('startAt').limit(30).snapshots().map((s) => s.docs.map(Rsvp.fromDoc).toList());
});

final myCheckinsProvider = StreamProvider<List<Checkin>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.checkins).where('uid', isEqualTo: uid).orderBy('at', descending: true).limit(100).snapshots().map((s) => s.docs.map(Checkin.fromDoc).toList());
});

final eventReviewsProvider = StreamProvider.family<List<Feedback>, String>((ref, eventId) => ref.watch(firestoreProvider).collection(Col.eventFeedback).where('eventId', isEqualTo: eventId).where('status', isEqualTo: 'published').orderBy('at', descending: true).limit(50).snapshots().map((s) => s.docs.map(Feedback.fromDoc).toList()));

/// Server-side personalized ranking (reason codes included). Falls back to chronological on any error.
class RankedFeedItem {
  const RankedFeedItem(this.eventId, this.score, this.reasons);
  final String eventId; final double score; final List<String> reasons;
}

final recommendedFeedProvider = FutureProvider<({String variant, List<RankedFeedItem> items})>((ref) async {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return (variant: 'chronological', items: <RankedFeedItem>[]);
  try {
    final r = await ref.read(functionsProvider).call('getRecommendedFeed', {'campusId': campusId});
    final items = ((r['items'] as List?) ?? const []).map((i) => RankedFeedItem(i['eventId'] as String, ((i['score'] as num?) ?? 0).toDouble(), ((i['reasons'] as List?) ?? const []).map((e) => e.toString()).toList())).toList();
    return (variant: r['variant'] as String? ?? 'chronological', items: items);
  } catch (_) {
    return (variant: 'chronological', items: <RankedFeedItem>[]);
  }
});

String reasonCopy(String code, Map<String, Tribe> tribes) => switch (code) {
      'because_of_tribe' => 'For your Tribe',
      'similar_to_attended' => 'Like events you attended',
      'friends_attending' => 'Friends are going',
      'popular_on_campus' => 'Popular on campus',
      'happening_soon' => 'Happening soon',
      _ => code,
    };

/// Event mutations — every one is a server call.
class EventActions {
  EventActions(this._fx);
  final CbFunctions _fx;
  Future<Map<String, dynamic>> rsvp(String eventId, {String source = 'detail'}) => _fx.call('createRsvp', {'eventId': eventId, 'source': source});
  Future<void> cancelRsvp(String eventId) => _fx.call('cancelRsvp', {'eventId': eventId});
  Future<Map<String, dynamic>> submitFeedback(String eventId, int rating, String? review, {bool anonymous = false}) => _fx.call('submitEventFeedback', {'eventId': eventId, 'rating': rating, 'review': review, 'anonymous': anonymous});
  Future<void> report(String campusId, String entityType, String entityId, String reason) => _fx.call('reportContent', {'campusId': campusId, 'entityType': entityType, 'entityId': entityId, 'reason': reason});
}

final eventActionsProvider = Provider<EventActions>((ref) => EventActions(ref.watch(functionsProvider)));
