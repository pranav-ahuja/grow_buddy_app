/// The cheapest end-to-end check there is: does the app start.
///
/// Worth its own file because everything else in this directory assumes it. If
/// the app cannot reach onboarding, the five other integration files will fail
/// in six different confusing ways instead of one obvious one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_OnboardingPage.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetDevice);

  testWidgets("smoke_app_launches | A signed-out launch reaches onboarding",
      (WidgetTester tester) async {
    await launchApp(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
    expect(find.text("Welcome to Grow Buddy!"), findsOneWidget);
  });

  testWidgets("smoke_no_exceptions | Launching throws nothing",
      (WidgetTester tester) async {
    // takeException returns whatever the framework caught during the pumps
    // above. On a real device this is where a missing asset or a plugin that
    // failed to register shows up — neither of which a widget test can see.
    await launchApp(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets("smoke_backend_is_reachable | The API the app is built against answers",
      (WidgetTester tester) async {
    // Not really a test of the app: it is the precondition for every other
    // integration test, reported once so a dead backend reads as one clear
    // failure rather than a cascade.
    final bool reachable = await backendIsReachable();

    expect(
      reachable,
      isTrue,
      reason: "GET $kApiBaseUrl/health did not answer. $backendUnreachableReason",
    );
  });

  testWidgets("smoke_onboarding_opens_the_dialog | The arrow offers a way in",
      (WidgetTester tester) async {
    await launchApp(tester);

    await tapAndSettle(tester, find.byType(FloatingActionButton));

    expect(buttonWithText("Login"), findsOneWidget);
    expect(buttonWithText("Sign up"), findsOneWidget);
  });
}
