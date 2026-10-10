import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

import '../core/env.dart';

/// One Google account per device, chosen freely by the user. Used for Drive
/// sync (drive.file: the app only sees files it created) and as the identity
/// for chat.
abstract final class GoogleAccount {
  static const scopes = [drive.DriveApi.driveFileScope];
  static bool _init = false;
  static GoogleSignInAccount? _account;

  static GoogleSignInAccount? get current => _account;

  static Future<void> _ensureInit() async {
    if (_init) return;
    await GoogleSignIn.instance.initialize(serverClientId: Env.googleWebClientId);
    _init = true;
  }

  /// Silent sign-in on app start (no UI). Returns null if never connected.
  static Future<GoogleSignInAccount?> restore() async {
    if (!Env.googleReady) return null;
    try {
      await _ensureInit();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      _account = null;
    }
    return _account;
  }

  /// Interactive: account picker + Drive consent.
  static Future<GoogleSignInAccount> connect() async {
    if (!Env.googleReady) {
      throw StateError('Google belum dikonfigurasi (GOOGLE_WEB_CLIENT_ID kosong).');
    }
    await _ensureInit();
    final acc = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    await acc.authorizationClient.authorizeScopes(scopes);
    _account = acc;
    return acc;
  }

  static Future<void> disconnect() async {
    await _ensureInit();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
    _account = null;
  }

  /// Authorised HTTP client for Google APIs. Prompts only if consent is
  /// missing or was revoked.
  static Future<gapis.AuthClient> client() async {
    final acc = _account ?? await restore();
    if (acc == null) throw StateError('Akun Google belum terhubung.');
    final auth =
        await acc.authorizationClient.authorizationForScopes(scopes) ??
        await acc.authorizationClient.authorizeScopes(scopes);
    return auth.authClient(scopes: scopes);
  }

  /// ID token for Supabase sign-in (requires serverClientId).
  static String? idToken() => _account?.authentication.idToken;
}
