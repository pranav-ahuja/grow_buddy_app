/// The login screen: the app's front door.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_ForgotPassword.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/mock_api.dart';

void main() {
  late FakeApi api;

  setUp(() => api = startTest());
  tearDown(endTest);

  Future<void> pumpLogin(WidgetTester tester) =>
      pumpScreen(tester, const GB_Login());

  Future<void> fillCredentials(
    WidgetTester tester, {
    String email = "pranav@example.com",
    String password = "supersecret123",
  }) async {
    await enterText(tester, fieldWithLabel("Email"), email);
    await enterText(tester, fieldWithLabel("Password"), password);
  }

  testWidgets("login_renders | Email, password, and a Login button are shown",
      (WidgetTester tester) async {
    await pumpLogin(tester);

    expect(fieldWithLabel("Email"), findsOneWidget);
    expect(fieldWithLabel("Password"), findsOneWidget);
    expect(buttonWithText("Login"), findsOneWidget);
    expect(find.text("Forgot Password?"), findsOneWidget);
    expect(find.text("New to Grow Buddy? Sign up now"), findsOneWidget);
  });

  testWidgets("login_password_starts_hidden | The password is obscured at first",
      (WidgetTester tester) async {
    await pumpLogin(tester);

    expect(isObscured(tester, "Password"), isTrue);
    expect(isObscured(tester, "Email"), isFalse);
  });

  testWidgets("login_visibility_toggle | The eye icon reveals and re-hides",
      (WidgetTester tester) async {
    // Login and SignUp once disagreed about which way this icon pointed, so
    // the pairing of icon and obscured-state is the thing worth pinning down.
    await pumpLogin(tester);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tapAndSettle(tester, find.byIcon(Icons.visibility_off));
    expect(isObscured(tester, "Password"), isFalse);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tapAndSettle(tester, find.byIcon(Icons.visibility));
    expect(isObscured(tester, "Password"), isTrue);
  });

  testWidgets("login_requires_both_fields | An empty form never calls the server",
      (WidgetTester tester) async {
    await pumpLogin(tester);

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(currentSnackBarText(tester), "Please enter email and password");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("login_requires_password | An email alone is not enough",
      (WidgetTester tester) async {
    await pumpLogin(tester);
    await enterText(tester, fieldWithLabel("Email"), "pranav@example.com");

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(currentSnackBarText(tester), "Please enter email and password");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("login_sends_typed_credentials | What was typed is what is posted",
      (WidgetTester tester) async {
    api.stub("/auth/login", body: tokenJson());
    await pumpLogin(tester);
    await fillCredentials(tester);

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(api.requestTo("/auth/login").body, {
      "email": "pranav@example.com",
      "password": "supersecret123",
    });
  });

  testWidgets("login_success_opens_dashboard | A teacher lands on the dashboard",
      (WidgetTester tester) async {
    api.stub("/auth/login", body: tokenJson());
    await pumpLogin(tester);
    await fillCredentials(tester);

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.byType(GB_Dashboard), findsOneWidget);
    expect(find.byType(GB_Login), findsNothing);
    expect(gLoginToken, kTestToken);
  });

  testWidgets("login_routes_on_needs_account_type | A roleless user completes their profile",
      (WidgetTester tester) async {
    // Keyed on needsAccountType, not isNewUser: somebody who abandoned the
    // profile screen is no longer new but still has no role, and routing on
    // isNewUser would strand them incomplete forever.
    api.stub("/auth/login",
        body: tokenJson(isNewUser: false, user: needsRoleUserJson()));
    await pumpLogin(tester);
    await fillCredentials(tester);

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.byType(GB_CompleteProfile), findsOneWidget);
    expect(find.byType(GB_Dashboard), findsNothing);
  });

  testWidgets("login_shows_server_error | The server wording reaches the user",
      (WidgetTester tester) async {
    api.stubError("/auth/login",
        status: 401, detail: "Invalid email or password");
    await pumpLogin(tester);
    await fillCredentials(tester, password: "wrongpassword");

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(currentSnackBarText(tester), "Invalid email or password");
    expect(find.byType(GB_Login), findsOneWidget);
    expect(gLoginToken, isNull);
  });

  testWidgets("login_stays_put_on_failure | A failed login keeps the form",
      (WidgetTester tester) async {
    api.stubError("/auth/login", status: 403, detail: "Account disabled");
    await pumpLogin(tester);
    await fillCredentials(tester);

    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.byType(GB_Dashboard), findsNothing);
    expect(buttonWithText("Login"), findsOneWidget);
  });

  testWidgets("login_disables_button_while_submitting | No double submissions",
      (WidgetTester tester) async {
    api.stub("/auth/login",
        body: tokenJson(), delay: const Duration(milliseconds: 400));
    await pumpLogin(tester);
    await fillCredentials(tester);

    await tester.tap(buttonWithText("Login"));
    await tester.pump();

    expect(buttonWithText("Logging in..."), findsOneWidget);
    expect(isButtonDisabled(tester, "Logging in..."), isTrue);

    await pumpFrames(tester, times: 8);
  });

  testWidgets("login_clear_email_icon | The cancel icon empties the field",
      (WidgetTester tester) async {
    await pumpLogin(tester);
    await enterText(tester, fieldWithLabel("Email"), "typo@example.com");

    await tapAndSettle(tester, find.byIcon(Icons.cancel_outlined));

    expect(fieldText(tester, "Email"), isEmpty);
  });

  testWidgets("login_remember_me | The checkbox toggles both ways",
      (WidgetTester tester) async {
    await pumpLogin(tester);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tapAndSettle(tester, find.byType(Checkbox));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    // The label beside it is a button too, sharing the same state.
    await tapAndSettle(tester, find.text("Remember me"));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets("login_to_forgot_password | The link opens the reset flow",
      (WidgetTester tester) async {
    await pumpLogin(tester);

    await tapAndSettle(tester, find.text("Forgot Password?"));

    expect(find.byType(GB_ForgotPassword), findsOneWidget);
  });

  testWidgets("login_to_signup | The link opens the sign-up form",
      (WidgetTester tester) async {
    await pumpLogin(tester);

    await tapAndSettle(tester, find.text("New to Grow Buddy? Sign up now"));

    expect(find.byType(GB_SignUp), findsOneWidget);
  });

  testWidgets("login_to_mobile_login | The phone button opens OTP login",
      (WidgetTester tester) async {
    await pumpLogin(tester);

    // Two round icon buttons sit side by side: Google first, phone second.
    await tapAndSettle(tester, find.byType(ElevatedButton).last);

    expect(find.byType(GB_MobileLogin), findsOneWidget);
  });
}
