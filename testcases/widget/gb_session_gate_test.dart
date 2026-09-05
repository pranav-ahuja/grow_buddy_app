/// The launch decision: resume a stored session, or start at onboarding.
///
/// This screen is the reason a user is not asked to log in again every morning,
/// and the reason a dropped wifi connection does not sign them out.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_OnboardingPage.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_SessionGate.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/mock_api.dart';
import '../support/mock_storage.dart';

void main() {
  late FakeApi api;

  setUp(() {
    api = startTest();
  });
  tearDown(endTest);

  Future<void> pumpGate(WidgetTester tester) async {
    await pumpScreen(tester, const GB_SessionGate());
    // The gate does two storage reads and a network call before it routes.
    await pumpFrames(tester, times: 10);
  }

  testWidgets("gate_shows_a_spinner | The gate itself is just a loading screen",
      (WidgetTester tester) async {
    // Stops before the storage read resolves: a moment later the gate has
    // already routed somewhere else and the spinner is gone.
    await pumpScreen(tester, const GB_SessionGate(), frames: 0);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets("gate_no_token_starts_onboarding | A fresh install sees the intro",
      (WidgetTester tester) async {
    await pumpGate(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
    // No point asking the server about a token we do not have.
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("gate_valid_token_opens_dashboard | A good session resumes",
      (WidgetTester tester) async {
    installStoredSession(token: "stored-jwt");
    api.stub("/auth/me", body: userJson(), method: "GET");

    await pumpGate(tester);

    expect(find.byType(GB_Dashboard), findsOneWidget);
    expect(gLoginToken, "stored-jwt");
  });

  testWidgets("gate_checks_the_token_with_me | The stored token is verified",
      (WidgetTester tester) async {
    // /me doubles as the token check: only the backend can say whether a JWT
    // has expired or been revoked.
    installStoredSession(token: "stored-jwt");
    api.stub("/auth/me", body: userJson(), method: "GET");

    await pumpGate(tester);

    expect(api.requestTo("/auth/me").bearerToken, "stored-jwt");
  });

  testWidgets("gate_refreshes_the_cached_user | The cache is rewritten from /me",
      (WidgetTester tester) async {
    final Map<String, String> storage =
        installStoredSession(token: "stored-jwt");
    api.stub("/auth/me",
        body: userJson(fullName: "Renamed On Server"), method: "GET");

    await pumpGate(tester);

    expect(gCurrentUser!.fullName, "Renamed On Server");
    expect(storage[kUserKey], contains("Renamed On Server"));
  });

  testWidgets("gate_roleless_user_completes_profile | A stored session can still owe a role",
      (WidgetTester tester) async {
    installStoredSession(token: "stored-jwt");
    api.stub("/auth/me", body: needsRoleUserJson(), method: "GET");

    await pumpGate(tester);

    expect(find.byType(GB_CompleteProfile), findsOneWidget);
  });

  testWidgets("gate_401_clears_the_session | A rejected token is thrown away",
      (WidgetTester tester) async {
    // The server has spoken: this token will never work again, so keeping it
    // would just mean retrying it on every launch forever.
    installStoredSession(token: "expired-jwt");
    api.stubError("/auth/me",
        status: 401, detail: "Could not validate credentials", method: "GET");

    await pumpGate(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
    expect(gLoginToken, isNull);
  });

  testWidgets("gate_403_clears_the_session | A forbidden token is also dropped",
      (WidgetTester tester) async {
    installStoredSession(token: "revoked-jwt");
    api.stubError("/auth/me",
        status: 403, detail: "Account disabled", method: "GET");

    await pumpGate(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
    expect(gLoginToken, isNull);
  });

  testWidgets("gate_offline_trusts_the_cache | A dropped connection is not a logout",
      (WidgetTester tester) async {
    // The whole point of this screen. A network failure says nothing about
    // whether the token is valid, so signing the user out over it would be
    // exactly the wrong reading of the evidence.
    installStoredSession(token: "stored-jwt");
    api.stubThrows("/auth/me", const SocketException("network is unreachable"));

    await pumpGate(tester);

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
    expect(gLoginToken, "stored-jwt");
  });

  testWidgets("gate_offline_keeps_the_token | An unreachable server leaves storage alone",
      (WidgetTester tester) async {
    final Map<String, String> storage =
        installStoredSession(token: "stored-jwt");
    api.stubThrows("/auth/me", const SocketException("no route to host"));

    await pumpGate(tester);

    expect(storage[kTokenKey], "stored-jwt");
  });

  testWidgets("gate_offline_without_a_cache_starts_over | Nothing to fall back on",
      (WidgetTester tester) async {
    // A token but no cached user: there is nothing to draw a dashboard from,
    // so onboarding is the only honest destination.
    installMockSecureStorage({kTokenKey: "stored-jwt"});
    api.stubThrows("/auth/me", const SocketException("offline"));

    await pumpGate(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
  });
}
