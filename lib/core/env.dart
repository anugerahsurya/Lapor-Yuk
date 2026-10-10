/// Build-time configuration, injected with
///   flutter build apk --dart-define-from-file=env.json
/// (see env.example.json). These are public client identifiers, not secrets:
/// access is enforced by Google OAuth and Supabase row-level security.
abstract final class Env {
  /// OAuth 2.0 "Web application" client ID from Google Cloud Console. Used as
  /// serverClientId so Android returns an ID token (needed by Supabase).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jdexdsmwyutpzyczkhlr.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get googleReady => googleWebClientId.isNotEmpty;
  static bool get chatReady => googleReady && supabaseAnonKey.isNotEmpty;
}
