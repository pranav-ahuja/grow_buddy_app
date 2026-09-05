/// The first screen a new user sees, and the dialog its arrow button opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_OnboardingPage.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Utilities_Onboarding/GB_Image_Slider.dart';

import '../support/harness.dart';
import '../support/mock_api.dart';

void main() {
  late FakeApi api;

  setUp(() => api = startTest());
  tearDown(endTest);

  Future<void> pumpOnboarding(WidgetTester tester) =>
      pumpScreen(tester, const OnBoardingPage());

  Future<void> openDialog(WidgetTester tester) async {
    await tapAndSettle(tester, find.byType(FloatingActionButton));
  }

  testWidgets("onboarding_renders | The carousel and welcome copy are shown",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);

    expect(find.byType(GB_ImageSlider), findsOneWidget);
    expect(find.text("Welcome to Grow Buddy!"), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets("onboarding_no_dialog_at_rest | Nothing is asked until the arrow",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets("onboarding_fab_opens_the_dialog | The arrow offers the four ways in",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);

    await openDialog(tester);

    expect(find.byType(Dialog), findsOneWidget);
    expect(buttonWithText("Login"), findsOneWidget);
    expect(buttonWithText("Sign up"), findsOneWidget);
    // Google and phone, as round icon buttons.
    expect(find.byType(ElevatedButton), findsNWidgets(4));
  });

  testWidgets("onboarding_to_login | The Login button opens the login form",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);
    await openDialog(tester);

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.byType(GB_Login), findsOneWidget);
  });

  testWidgets("onboarding_to_signup | The Sign up button opens the form",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);
    await openDialog(tester);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(find.byType(GB_SignUp), findsOneWidget);
  });

  testWidgets("onboarding_to_mobile_login | The phone button opens OTP login",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);
    await openDialog(tester);

    await tapAndSettle(tester, find.byType(ElevatedButton).last);

    expect(find.byType(GB_MobileLogin), findsOneWidget);
  });

  testWidgets("onboarding_makes_no_calls | Browsing the intro contacts nobody",
      (WidgetTester tester) async {
    await pumpOnboarding(tester);
    await openDialog(tester);

    expect(api.madeNoCalls, isTrue);
  });
}
