import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;

import '../core/config/app_config.dart';
import '../core/constants/feature_flags.dart';
import '../firebase_options.dart';

/// Initialises Firebase, emulators (dev only), App Check, Crashlytics, Remote
/// Config defaults, fonts and timezone data. Safe to call once.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  GoogleFonts.config.allowRuntimeFetching = !AppConfig.useEmulators || kIsWeb;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (AppConfig.useEmulators) {
    final host = kIsWeb || defaultTargetPlatform != TargetPlatform.android ? AppConfig.emulatorHost : (AppConfig.emulatorHost == 'localhost' ? '10.0.2.2' : AppConfig.emulatorHost);
    await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, AppConfig.firestorePort);
    FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion).useFunctionsEmulator(host, AppConfig.functionsPort);
    await FirebaseStorage.instance.useStorageEmulator(host, AppConfig.storagePort);
    debugPrint('CampusBuzz → Firebase emulators at $host');
  } else {
    // App Check: Play Integrity / DeviceCheck in production, debug providers elsewhere.
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AppConfig.isProduction ? AndroidProvider.playIntegrity : AndroidProvider.debug,
        appleProvider: AppConfig.isProduction ? AppleProvider.deviceCheck : AppleProvider.debug,
        webProvider: AppConfig.appCheckWebRecaptchaKey.isNotEmpty ? ReCaptchaV3Provider(AppConfig.appCheckWebRecaptchaKey) : null,
      );
    } catch (e) {
      debugPrint('App Check activation skipped: $e');
    }
    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  }

  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 40 * 1024 * 1024);

  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(RemoteConfigSettings(fetchTimeout: const Duration(seconds: 8), minimumFetchInterval: AppConfig.isProduction ? const Duration(hours: 1) : const Duration(minutes: 1)));
    await rc.setDefaults({for (final f in FeatureFlag.values) f.key: f.defaultValue});
    if (!AppConfig.useEmulators) await rc.fetchAndActivate();
  } catch (e) {
    debugPrint('Remote Config unavailable, using local defaults: $e');
  }
}
