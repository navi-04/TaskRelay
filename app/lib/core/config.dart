/// Build-time settings. Override the server with `--dart-define=API_BASE=http://127.0.0.1:3000`
/// (for example through `adb reverse tcp:3000 tcp:3000` while developing).
class Config {
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://taskrelay.vercel.app');

  /// Public pages the app links to (served by the same site).
  static String get privacyUrl => '$apiBase/privacy';
  static String get accountDeletionUrl => '$apiBase/account-deletion';
}
