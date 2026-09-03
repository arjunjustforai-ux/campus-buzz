/// Build-time configuration supplied via `--dart-define` / `--dart-define-from-file`.
/// Never put secrets here; only public client configuration.
enum AppEnvironment { development, staging, production }

abstract final class AppConfig {
  static const String _env = String.fromEnvironment('CB_ENV', defaultValue: 'development');
  static const bool useEmulators = bool.fromEnvironment('USE_EMULATORS', defaultValue: false);
  static const String emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
  static const String posthogKey = String.fromEnvironment('POSTHOG_KEY', defaultValue: '');
  static const String posthogHost = String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://app.posthog.com');
  static const String appCheckWebRecaptchaKey = String.fromEnvironment('APP_CHECK_WEB_RECAPTCHA_KEY', defaultValue: '');
  static const String deepLinkBaseUrl = String.fromEnvironment('DEEP_LINK_BASE_URL', defaultValue: 'https://campusbuzz.app');
  static const String functionsRegion = String.fromEnvironment('CB_FUNCTIONS_REGION', defaultValue: 'asia-south1');

  static AppEnvironment get environment => switch (_env) {
        'production' => AppEnvironment.production,
        'staging' => AppEnvironment.staging,
        _ => AppEnvironment.development,
      };

  static bool get isProduction => environment == AppEnvironment.production;

  /// Email verification can only be skipped against the emulator, never in a real project.
  static bool get allowEmulatorAuthShortcuts => useEmulators && !isProduction;

  static const int firestorePort = 8080;
  static const int authPort = 9099;
  static const int functionsPort = 5001;
  static const int storagePort = 9199;
}
