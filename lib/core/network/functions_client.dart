import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../errors/app_error.dart';

/// Typed wrapper around callable Cloud Functions. All economy / security
/// sensitive writes go through here — never through direct Firestore writes.
class CbFunctions {
  CbFunctions(this._functions);
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic>? data]) async {
    try {
      final result = await _functions.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 60))).call<dynamic>(data ?? <String, dynamic>{});
      final d = result.data;
      if (d is Map) return Map<String, dynamic>.from(d);
      return {'value': d};
    } catch (e) {
      throw AppError.from(e);
    }
  }
}

final functionsProvider = Provider<CbFunctions>((ref) {
  final f = FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);
  return CbFunctions(f);
});
