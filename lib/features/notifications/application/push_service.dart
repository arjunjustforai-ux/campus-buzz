import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/collections.dart';
import '../../../core/navigation/router.dart';

/// FCM registration + foreground/background handling + deep-link routing.
/// Delivery scheduling lives on the server (notification_jobs); the app only
/// registers tokens and routes taps.
class PushService {
  PushService(this._ref);
  final Ref _ref;
  StreamSubscription<RemoteMessage>? _onMessage, _onOpened;
  String? _registeredForUid;
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    _ref.listen<String?>(currentUidProvider, (_, uid) => _syncToken(uid), fireImmediately: true);
    if (AppConfig.useEmulators && !kIsWeb) return; // no FCM in emulator
    try {
      final m = FirebaseMessaging.instance;
      _onMessage = FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null) _ref.read(foregroundNotificationProvider.notifier).show((title: n.title ?? '', body: n.body ?? '', route: msg.data['route'] as String?));
      });
      _onOpened = FirebaseMessaging.onMessageOpenedApp.listen((msg) => _open(msg));
      final initial = await m.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      debugPrint('push init skipped: $e');
    }
  }

  void _open(RemoteMessage msg) {
    final route = msg.data['route'] as String?;
    _ref.read(analyticsProvider).track('notification_opened', {'route': route});
    if (route != null && route.isNotEmpty) _ref.read(routerProvider).push(route);
  }

  Future<void> _syncToken(String? uid) async {
    if (uid == null || uid == _registeredForUid) return;
    if (AppConfig.useEmulators && !kIsWeb) { _registeredForUid = uid; return; }
    try {
      final m = FirebaseMessaging.instance;
      final settings = await m.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await m.getToken();
      if (token == null) return;
      await _ref.read(firestoreProvider).collection(Col.users).doc(uid).update({'fcmTokens': FieldValue.arrayUnion([token])});
      _registeredForUid = uid;
      m.onTokenRefresh.listen((t) => _ref.read(firestoreProvider).collection(Col.users).doc(uid).update({'fcmTokens': FieldValue.arrayUnion([t])}));
    } catch (e) {
      debugPrint('push token sync skipped: $e');
    }
  }

  void dispose() { _onMessage?.cancel(); _onOpened?.cancel(); }
}

final pushServiceProvider = Provider<PushService>((ref) { final s = PushService(ref); ref.onDispose(s.dispose); return s; });

typedef ForegroundNotification = ({String title, String body, String? route});

/// Foreground notification banner state (rendered by HomeScreen scaffold).
class ForegroundNotificationNotifier extends Notifier<ForegroundNotification?> {
  @override
  ForegroundNotification? build() => null;
  void show(ForegroundNotification n) => state = n;
  void clear() => state = null;
}

final foregroundNotificationProvider = NotifierProvider<ForegroundNotificationNotifier, ForegroundNotification?>(ForegroundNotificationNotifier.new);
