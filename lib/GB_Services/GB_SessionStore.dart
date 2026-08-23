import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';

/// Where the signed-in session lives between app launches.
///
/// Secure storage rather than SharedPreferences because the token is a bearer
/// credential: anything holding it *is* the user until it expires. On Android
/// this lands in EncryptedSharedPreferences (backed by the Keystore), on iOS in
/// the Keychain — neither is readable by other apps or by `adb backup`.
///
/// The user object is cached alongside it so a launch without network can still
/// draw the dashboard instead of bouncing the user back to onboarding.
class GB_SessionStore {
  static const String _tokenKey = "gb_auth_token";
  static const String _userKey = "gb_auth_user";

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    // Without this, Android falls back to plain SharedPreferences on some
    // devices whose Keystore is unreliable.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> save({
    required String token,
    required GB_User user,
  }) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } catch (error) {
      // A device that cannot persist is a degraded session, not a failed login
      // — the in-memory globals are already set, so let the user carry on.
      debugPrint("[GB_SessionStore] could not save session: $error");
    }
  }

  /// Rewrites only the cached user, for `PATCH /me`, which returns a fresh user
  /// but no new token.
  static Future<void> saveUser(GB_User user) async {
    try {
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } catch (error) {
      debugPrint("[GB_SessionStore] could not save user: $error");
    }
  }

  static Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (error) {
      debugPrint("[GB_SessionStore] could not read token: $error");
      return null;
    }
  }

  static Future<GB_User?> readUser() async {
    try {
      final String? raw = await _storage.read(key: _userKey);
      if (raw == null) return null;
      return GB_User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      // Most likely a cache written by an older build whose shape has since
      // changed. Not worth failing a launch over — /me will refill it.
      debugPrint("[GB_SessionStore] could not read user: $error");
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (error) {
      debugPrint("[GB_SessionStore] could not clear session: $error");
    }
  }
}
