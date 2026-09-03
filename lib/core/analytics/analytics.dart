import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_providers.dart';
import '../config/app_config.dart';
import '../constants/collections.dart';
import '../models/models.dart';

/// Analytics abstraction: first-party Firestore log (authoritative funnel data),
/// Firebase Analytics, and optional PostHog. Never blocks UI, never throws.
abstract interface class AnalyticsSink {
  Future<void> track(String event, Map<String, Object?> props);
}

class FirebaseAnalyticsSink implements AnalyticsSink {
  @override
  Future<void> track(String event, Map<String, Object?> props) async {
    try {
      await FirebaseAnalytics.instance.logEvent(name: event.length > 40 ? event.substring(0, 40) : event, parameters: props.map((k, v) => MapEntry(k, v is num || v is String ? v! : v.toString())));
    } catch (_) {}
  }
}

class FirestoreAnalyticsSink implements AnalyticsSink {
  FirestoreAnalyticsSink(this.db);
  final FirebaseFirestore db;
  @override
  Future<void> track(String event, Map<String, Object?> props) async {
    if (props['uid'] == null) return; // rules require own uid
    try {
      final doc = {'event': event, ...props, 'at': FieldValue.serverTimestamp()}..removeWhere((k, v) => v == null);
      if (doc.length > 14) doc.removeWhere((k, v) => !const {'event', 'uid', 'campusId', 'eventId', 'organizerId', 'tribeIds', 'source', 'feedVariant', 'role', 'at', 'screen', 'questId', 'rewardId'}.contains(k));
      await db.collection(Col.analyticsEvents).add(doc);
    } catch (_) {}
  }
}

class PostHogSink implements AnalyticsSink {
  PostHogSink(this.key, this.host);
  final String key, host;
  @override
  Future<void> track(String event, Map<String, Object?> props) async {
    try {
      await http.post(Uri.parse('$host/capture/'), headers: {'content-type': 'application/json'}, body: jsonEncode({'api_key': key, 'event': event, 'distinct_id': props['uid'] ?? 'anonymous', 'properties': props})).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

class Analytics {
  Analytics(this._sinks, this._context);
  final List<AnalyticsSink> _sinks;
  final Map<String, Object?> Function() _context;

  void track(String event, [Map<String, Object?> props = const {}]) {
    final merged = {..._context(), ...props};
    for (final s in _sinks) {
      s.track(event, merged);
    }
    if (kDebugMode) debugPrint('[analytics] $event ${merged['eventId'] ?? ''}');
  }
}

final analyticsProvider = Provider<Analytics>((ref) {
  final sinks = <AnalyticsSink>[FirestoreAnalyticsSink(ref.watch(firestoreProvider))];
  if (!AppConfig.useEmulators) sinks.add(FirebaseAnalyticsSink());
  if (AppConfig.posthogKey.isNotEmpty) sinks.add(PostHogSink(AppConfig.posthogKey, AppConfig.posthogHost));
  return Analytics(sinks, () {
    final profile = ref.read(userProfileProvider).value;
    final roles = ref.read(rolesProvider);
    return {'uid': profile?.uid, 'campusId': profile?.activeCampusId, 'feedVariant': profile?.feedVariant, 'role': roles.contains(Role.organizer) ? 'organizer' : roles.contains(Role.campusAdmin) ? 'campus_admin' : 'student'};
  });
});
