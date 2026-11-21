class AppConfig {
  /// API base URL. Defaults to the local dev API; override at build time:
  /// `flutter build web --release --dart-define=API_BASE_URL=https://your-api.vercel.app`
  /// On Netlify, set the `API_BASE_URL` build environment variable in the site
  /// dashboard (or it falls back to http://127.0.0.1:4000).
  ///
  /// 127.0.0.1 rather than localhost: on some Linux setups `localhost`
  /// resolves to ::1 first while the API binds IPv4 0.0.0.0 only.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:4000',
  );

  /// When true the app uses the bundled, persistent on-device demo store
  /// instead of calling the API. This makes the APK fully usable without a
  /// hosted backend. Set `--dart-define=OFFLINE_MODE=false` to use the API.
  /// On Netlify, set the `OFFLINE_MODE` build environment variable to `false`.
  static const bool offlineMode = bool.fromEnvironment(
    'OFFLINE_MODE',
    defaultValue: true,
  );
}
