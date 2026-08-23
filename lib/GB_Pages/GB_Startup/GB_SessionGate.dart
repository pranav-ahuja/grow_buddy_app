import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_OnboardingPage.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The first screen after the splash: decides whether this launch resumes a
/// stored session or starts at onboarding.
///
/// It is the launch-time counterpart of `gRouteAfterAuth`, and answers the same
/// question the same way — `needsAccountType` goes to [GB_CompleteProfile],
/// everything else to [GB_Dashboard].
class GB_SessionGate extends StatefulWidget {
  const GB_SessionGate({super.key});

  @override
  State<GB_SessionGate> createState() => _GB_SessionGateState();
}

class _GB_SessionGateState extends State<GB_SessionGate> {
  @override
  void initState() {
    super.initState();
    _resolveSession();
  }

  Future<void> _resolveSession() async {
    final String? token = await GB_SessionStore.readToken();

    if (token == null) {
      _goTo(const OnBoardingPage());
      return;
    }

    final GB_User? cachedUser = await GB_SessionStore.readUser();

    try {
      // `/me` doubles as the token check: the backend rejects an expired or
      // revoked JWT, which is the only reliable way to know it is still good.
      final GB_User user = await GB_AuthApi.me(token);
      gRestoreSession(token: token, user: user);
      await GB_SessionStore.save(token: token, user: user);
      _goToSignedIn(user);
    } on GB_ApiException catch (error) {
      final int? status = error.statusCode;

      if (status == 401 || status == 403) {
        // The server has spoken: this token is no good. Drop it, so the next
        // launch doesn't retry a credential that will never work again.
        debugPrint("[GB_SessionGate] stored token rejected ($status)");
        await gClearSession();
        _goTo(const OnBoardingPage());
        return;
      }

      // Anything else is the network or the server being unreachable, which
      // says nothing about the token. Signing the user out because their wifi
      // dropped is exactly the behaviour this screen exists to prevent, so
      // trust the cache and let the next call re-check.
      debugPrint("[GB_SessionGate] could not reach /me: ${error.message}");
      if (cachedUser != null) {
        gRestoreSession(token: token, user: cachedUser);
        _goToSignedIn(cachedUser);
      } else {
        _goTo(const OnBoardingPage());
      }
    }
  }

  void _goToSignedIn(GB_User user) {
    _goTo(
      user.needsAccountType
          ? const GB_CompleteProfile(isNewUser: false)
          : const GB_Dashboard(),
    );
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kPrimaryColor2,
      body: Center(
        child: CircularProgressIndicator(color: kPrimaryColor1),
      ),
    );
  }
}
