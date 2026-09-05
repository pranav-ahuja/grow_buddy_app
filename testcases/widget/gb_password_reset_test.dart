/// The forgot-password flow.
///
/// These three screens are **not wired to any backend** — each one validates
/// its input and then simply navigates on, with a `TODO(backend)` where the
/// call belongs. Every test here asserts the app made no HTTP call, so the fact
/// that the flow is a shell stays visible in the report instead of being
/// forgotten and shipped as though it worked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CreateNewPassword.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_ForgotPassword.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_VerifyEmail.dart';
import 'package:pinput/pinput.dart';

import '../support/harness.dart';
import '../support/mock_api.dart';

const String _email = "pranav@example.com";

void main() {
  late FakeApi api;

  setUp(() => api = startTest());
  tearDown(endTest);

  group("GB_ForgotPassword", () {
    Future<void> pumpForgot(WidgetTester tester) =>
        pumpScreen(tester, const GB_ForgotPassword());

    testWidgets("forgot_renders | An email field and a Next button",
        (WidgetTester tester) async {
      await pumpForgot(tester);

      expect(fieldWithLabel("Email"), findsOneWidget);
      expect(buttonWithText("Next"), findsOneWidget);
    });

    testWidgets("forgot_requires_an_email | A blank field is refused",
        (WidgetTester tester) async {
      await pumpForgot(tester);

      await tapAndSettle(tester, buttonWithText("Next"));

      expect(currentSnackBarText(tester),
          "Please enter your registered email ID");
    });

    testWidgets("forgot_moves_on | A filled email opens the code screen",
        (WidgetTester tester) async {
      await pumpForgot(tester);
      await enterText(tester, fieldWithLabel("Email"), _email);

      await tapAndSettle(tester, buttonWithText("Next"));

      expect(find.byType(GB_VerifyEmail), findsOneWidget);
    });

    testWidgets("forgot_carries_the_email_forward | The next screen is told who",
        (WidgetTester tester) async {
      await pumpForgot(tester);
      await enterText(tester, fieldWithLabel("Email"), "  $_email  ");

      await tapAndSettle(tester, buttonWithText("Next"));

      expect(
        tester.widget<GB_VerifyEmail>(find.byType(GB_VerifyEmail)).emailID,
        _email,
      );
    });

    testWidgets("forgot_calls_no_backend | Nothing is actually requested",
        (WidgetTester tester) async {
      // TODO(backend) at GB_ForgotPassword.dart:46 — no reset endpoint exists.
      await pumpForgot(tester);
      await enterText(tester, fieldWithLabel("Email"), _email);

      await tapAndSettle(tester, buttonWithText("Next"));

      expect(api.madeNoCalls, isTrue);
    });
  });

  group("GB_VerifyEmail", () {
    Future<void> pumpVerifyEmail(WidgetTester tester) =>
        pumpScreen(tester, const GB_VerifyEmail(emailID: _email));

    testWidgets("verify_email_renders | A code box and a Done button",
        (WidgetTester tester) async {
      await pumpVerifyEmail(tester);

      expect(find.byType(Pinput), findsOneWidget);
      expect(buttonWithText("Done"), findsOneWidget);
    });

    testWidgets("verify_email_requires_six_digits | A short code is refused",
        (WidgetTester tester) async {
      await pumpVerifyEmail(tester);
      await enterText(tester, find.byType(Pinput), "123");

      await tapAndSettle(tester, buttonWithText("Done"));

      expect(currentSnackBarText(tester),
          "Please enter the 6 digit code we emailed you");
    });

    testWidgets("verify_email_moves_on | A full code opens the password screen",
        (WidgetTester tester) async {
      await pumpVerifyEmail(tester);
      await enterText(tester, find.byType(Pinput), "123456");

      await tapAndSettle(tester, buttonWithText("Done"));

      expect(find.byType(GB_CreateNewPassword), findsOneWidget);
    });

    testWidgets("verify_email_accepts_any_code | Nothing checks it yet",
        (WidgetTester tester) async {
      // The point of this test is the gap: with no reset endpoint, six
      // arbitrary digits get through. It should start failing the day the
      // backend lands, which is exactly when someone should look at it.
      await pumpVerifyEmail(tester);
      await enterText(tester, find.byType(Pinput), "000000");

      await tapAndSettle(tester, buttonWithText("Done"));

      expect(find.byType(GB_CreateNewPassword), findsOneWidget);
      expect(api.madeNoCalls, isTrue);
    });

    testWidgets("verify_email_resend_is_cosmetic | Resend only shows a message",
        (WidgetTester tester) async {
      await pumpVerifyEmail(tester);

      // A plain TextButton here, unlike the OTP screen's elevated one, so
      // buttonWithText (which looks for ElevatedButton) would miss it.
      await tapAndSettle(tester, find.text("Resend Code"));

      expect(currentSnackBarText(tester),
          "Verification code sent to $_email");
      expect(api.madeNoCalls, isTrue);
    });
  });

  group("GB_CreateNewPassword", () {
    Future<void> pumpNewPassword(WidgetTester tester) =>
        pumpScreen(tester, const GB_CreateNewPassword(emailID: _email));

    testWidgets("new_password_renders | Two password fields are shown",
        (WidgetTester tester) async {
      await pumpNewPassword(tester);

      expect(fieldWithLabel("Password"), findsOneWidget);
      expect(fieldWithLabel("Re-enter Password"), findsOneWidget);
    });

    testWidgets("new_password_requires_both | An empty form is refused",
        (WidgetTester tester) async {
      await pumpNewPassword(tester);

      await tapAndSettle(tester, find.byType(ElevatedButton).first);

      expect(currentSnackBarText(tester),
          "Please enter and re-enter your new password");
    });

    testWidgets("new_password_requires_a_match | A typo is caught",
        (WidgetTester tester) async {
      await pumpNewPassword(tester);
      await enterText(tester, fieldWithLabel("Password"), "supersecret123");
      await enterText(
          tester, fieldWithLabel("Re-enter Password"), "supersecret124");

      await tapAndSettle(tester, find.byType(ElevatedButton).first);

      expect(currentSnackBarText(tester), "The two passwords do not match");
    });

    testWidgets("new_password_returns_to_login | The flow ends at the login form",
        (WidgetTester tester) async {
      await pumpNewPassword(tester);
      await enterText(tester, fieldWithLabel("Password"), "supersecret123");
      await enterText(
          tester, fieldWithLabel("Re-enter Password"), "supersecret123");

      await tapAndSettle(tester, find.byType(ElevatedButton).first);

      expect(find.byType(GB_Login), findsOneWidget);
    });

    testWidgets("new_password_changes_nothing | No password is actually reset",
        (WidgetTester tester) async {
      // The screen says "Password changed. Please log in." while sending
      // nothing anywhere. Worth a failing-looking test the day it is wired up.
      await pumpNewPassword(tester);
      await enterText(tester, fieldWithLabel("Password"), "supersecret123");
      await enterText(
          tester, fieldWithLabel("Re-enter Password"), "supersecret123");

      await tapAndSettle(tester, find.byType(ElevatedButton).first);

      expect(api.madeNoCalls, isTrue);
    });
  });
}
