import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';

/// App Links / Universal Links via `app_links`. https://campusbuzz.app/e/{id}
/// and campusbuzz://e/{id} both resolve to /events/{id}.
class DeepLinkService {
  DeepLinkService(this._router);
  final GoRouter _router;
  StreamSubscription<Uri>? _sub;

  Future<void> init() async {
    if (kIsWeb) return; // web uses real URLs handled by go_router
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _handle(initial);
      _sub = links.uriLinkStream.listen(_handle);
    } catch (e) {
      debugPrint('deep links unavailable: $e');
    }
  }

  void _handle(Uri uri) {
    final path = toRoute(uri);
    if (path != null) _router.push(path);
  }

  static String? toRoute(Uri uri) {
    final segs = uri.pathSegments;
    if (segs.isEmpty) return null;
    if ((segs[0] == 'e' || segs[0] == 'events') && segs.length >= 2) return '/events/${segs[1]}';
    if (segs[0] == 'r' && segs.length >= 2) return '/register?ref=${segs[1]}';
    if (segs[0] == 'q' && segs.length >= 2) return '/quests/${segs[1]}';
    return '/${segs.join('/')}';
  }

  static String eventShareUrl(String eventId) => '${AppConfig.deepLinkBaseUrl}/e/$eventId';
  static String referralUrl(String code) => '${AppConfig.deepLinkBaseUrl}/r/$code';

  void dispose() => _sub?.cancel();
}
