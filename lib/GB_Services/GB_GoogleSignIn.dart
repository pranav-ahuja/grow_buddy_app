import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// Thin wrapper over the google_sign_in plugin that hands back an **ID token**
/// for [GB_AuthApi.loginWithGoogle].
///
/// Everything here throws [GB_ApiException] so a screen can catch that one type
/// for both plugin and backend failures.
///
/// This targets google_sign_in 7.x, whose API differs from 6.x: there is a
/// single [GoogleSignIn.instance], [GoogleSignIn.initialize] must be awaited
/// exactly once before anything else, and [GoogleSignIn.authenticate] throws on
/// cancellation rather than returning null.
class GB_GoogleSignIn {
  /// Prefix so the whole Google flow can be followed with
  /// `adb logcat | grep GB_GoogleSignIn`. debugPrint is stripped from release
  /// builds, so this costs nothing in production.
  static const String _logTag = "[GB_GoogleSignIn]";

  /// Held so [initialize] runs once even if the button is tapped twice quickly;
  /// the plugin documents repeat calls as undefined behavior.
  static Future<void>? _initialization;

  static Future<void> _ensureInitialized() async {
    final Future<void> pending = _initialization ??=
        GoogleSignIn.instance.initialize(
      // Empty means "not configured yet", and the plugin expects null for that
      // rather than a blank string.
      clientId: kGoogleIosClientId.isEmpty ? null : kGoogleIosClientId,
      serverClientId:
          kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
    );

    try {
      await pending;
    } catch (_) {
      // Don't cache a failed initialization, or every later attempt replays the
      // same error even once the configuration is fixed.
      _initialization = null;
      rethrow;
    }
  }

  /// Runs the interactive Google flow and returns the ID token to POST to
  /// `/auth/google`.
  ///
  /// Returns null when the user backs out — the caller should stay put silently
  /// rather than showing an error.
  static Future<String?> signInAndGetIdToken() async {
    // Android needs the Web client ID to mint an ID token at all. Checking here
    // turns a confusing "canceled"/null-token failure into a clear cause.
    if (defaultTargetPlatform == TargetPlatform.android &&
        kGoogleServerClientId.isEmpty) {
      throw GB_ApiException(
        "Google sign-in isn't configured yet. Set kGoogleServerClientId in "
        "GB_Constants.dart to the Web OAuth client ID.",
      );
    }

    try {
      await _ensureInitialized();

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw GB_ApiException(
          "Google sign-in isn't supported on this platform.",
        );
      }

      final GoogleSignInAccount account =
          await GoogleSignIn.instance.authenticate();

      final String? idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        // Almost always a serverClientId that is missing or doesn't match the
        // Web client registered in the Cloud Console.
        throw GB_ApiException(
          "Google didn't return an ID token. Check that "
          "kGoogleServerClientId is the Web OAuth client ID.",
        );
      }

      debugPrint(
        "$_logTag got ID token for ${account.email} (${idToken.length} chars)",
      );
      return idToken;
    } on GoogleSignInException catch (error) {
      debugPrint(
        "$_logTag GoogleSignInException code=${error.code.name} "
        "description=${error.description}",
      );
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          // The plugin cannot tell a real cancellation apart from several
          // configuration errors: Android's Credential Manager reports both as
          // "canceled". Staying silent is right for the user but leaves no
          // trace to debug with, so say so in the log at least.
          debugPrint(
            "$_logTag treating as cancellation. If you did NOT dismiss the "
            "sheet, this is almost certainly a configuration mismatch - check "
            "the Android client's SHA-1 and package name, and that the "
            "signed-in account is a test user on the OAuth consent screen.",
          );
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError:
          throw GB_ApiException(
            "Google sign-in is misconfigured. Check the Android client's "
            "package name and SHA-1, and that kGoogleServerClientId is the "
            "Web OAuth client ID.",
          );
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw GB_ApiException(
            "Google Play services is unavailable or out of date on this "
            "device.",
          );
        case GoogleSignInExceptionCode.uiUnavailable:
          throw GB_ApiException(
            "Google sign-in couldn't open. Try again.",
          );
        default:
          throw GB_ApiException(
            "Google sign-in failed: ${error.description ?? error.code.name}",
          );
      }
    }
  }

  /// Clears the cached Google account so the next sign-in shows the account
  /// picker again. Failures here are not worth interrupting a logout for.
  static Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Already signed out, or never initialized.
    }
  }
}
