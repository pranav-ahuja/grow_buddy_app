import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_GoogleSignIn.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// What happens after any successful sign-up, login, OTP verification, or
/// Google sign-in. Every auth screen funnels through here so the rule lives in
/// one place instead of being restated four times.
///
/// The rule: `needsAccountType` sends the user to [GB_CompleteProfile],
/// everything else goes to [GB_Dashboard].
///
/// Deliberately keyed on `needsAccountType` rather than `isNewUser`. Someone
/// who abandons the profile screen is no longer "new" the next time they log
/// in, but still has no role — routing on `isNewUser` would strand them with a
/// permanently incomplete profile. `isNewUser` only picks the wording.
void gRouteAfterAuth(BuildContext context, GB_AuthResult result) {
  // Not awaited: `gSetSession` fills the globals synchronously and only the
  // disk write is async, so there is nothing for the navigation below to wait
  // for. Blocking the route change on a Keystore round trip would just stall
  // the screen.
  unawaited(gSetSession(result));

  // pushAndRemoveUntil, not push: the login/sign-up stack is finished with, and
  // leaving it in place would let Back return to a login form while signed in.
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (context) => result.user.needsAccountType
          ? GB_CompleteProfile(isNewUser: result.isNewUser)
          : const GB_Dashboard(),
    ),
    (route) => false,
  );
}

/// Ends the session and returns to the login screen.
///
/// Shared by the dashboard's "Logout" and by the escape hatch on
/// [GB_CompleteProfile], because both mean the same thing: this device is no
/// longer signed in as anybody.
///
/// Lands on [GB_Login] rather than onboarding: someone who just logged out has
/// already seen the intro, and what they want next is the form — either to sign
/// back in or to reach sign-up, which the login page links to.
///
/// The Google sign-out matters even for a phone login — if the user arrived via
/// Google, skipping it leaves the account cached, and the next sign-in silently
/// reuses it instead of showing the picker. That is exactly the "let me use a
/// different account" case, so it must not be skipped.
Future<void> gSignOut(BuildContext context) async {
  // Captured before the awaits: using `context` afterwards would be a
  // use-after-async-gap if the widget went away mid-flight.
  final NavigatorState navigator = Navigator.of(context);

  await GB_GoogleSignIn.signOut();
  // Awaited: the stored token must be gone before the login page is shown, or a
  // kill-and-relaunch in between would sign the user straight back in.
  await gClearSession();

  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (context) => const GB_Login()),
    (route) => false,
  );
}

/// Guards against a second Google flow being launched while one is open — the
/// icon buttons are small and easy to double-tap, and the onboarding dialog has
/// no state of its own to disable them with.
bool _googleSignInInFlight = false;

/// The whole Google button action: get an ID token from Google, trade it for a
/// GrowBuddy session, then route.
///
/// Shared by the login page, the sign-up page, and the onboarding dialog.
Future<void> gSignInWithGoogle(BuildContext context) async {
  if (_googleSignInInFlight) return;
  _googleSignInInFlight = true;

  try {
    final String? idToken = await GB_GoogleSignIn.signInAndGetIdToken();

    // Null means the user backed out of the Google sheet — not an error, so
    // stay put and say nothing.
    if (idToken == null) {
      debugPrint("[gSignInWithGoogle] no ID token, stopping quietly");
      return;
    }

    debugPrint("[gSignInWithGoogle] exchanging ID token at $kGoogleLoginUrl");
    final GB_AuthResult result = await GB_AuthApi.loginWithGoogle(idToken);
    debugPrint(
      "[gSignInWithGoogle] backend accepted it: user=${result.user.fullName} "
      "isNewUser=${result.isNewUser} "
      "needsAccountType=${result.user.needsAccountType}",
    );

    if (!context.mounted) return;
    gRouteAfterAuth(context, result);
  } on GB_ApiException catch (error) {
    debugPrint("[gSignInWithGoogle] failed: ${error.message}");
    if (!context.mounted) return;
    gShowSnack(context, error.message);
  } finally {
    _googleSignInInFlight = false;
  }
}

/// The backend hands back errors already worded for humans, so they go straight
/// to the user.
void gShowSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
