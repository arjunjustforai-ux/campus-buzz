// Firebase project configuration.
//
// These values target the LOCAL EMULATOR project `demo-campusbuzz` and are safe
// to commit. For staging/production run:
//   flutterfire configure --project=<project-id> --out=lib/firebase_options_<env>.dart
// and select the file via `--dart-define=CB_ENV=staging|production` (see
// lib/core/config/app_config.dart and docs/DEPLOYMENT.md). Real option files are
// git-ignored (lib/firebase_options_*.dart).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  static const String projectId = 'demo-campusbuzz';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-campusbuzz-web-key',
    appId: '1:000000000000:web:campusbuzzdemo',
    messagingSenderId: '000000000000',
    projectId: projectId,
    authDomain: 'demo-campusbuzz.firebaseapp.com',
    storageBucket: 'demo-campusbuzz.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-campusbuzz-android-key',
    appId: '1:000000000000:android:campusbuzzdemo',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: 'demo-campusbuzz.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-campusbuzz-ios-key',
    appId: '1:000000000000:ios:campusbuzzdemo',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: 'demo-campusbuzz.appspot.com',
    iosBundleId: 'app.campusbuzz.campusbuzz',
  );
}
