/// The sign-up form, including the role dropdown that once defaulted to
/// teacher and quietly mis-registered anyone who skipped it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/mock_api.dart';

void main() {
  late FakeApi api;

  setUp(() => api = startTest());
  tearDown(endTest);

  Future<void> pumpSignUp(WidgetTester tester) =>
      pumpScreen(tester, const GB_SignUp());

  /// Picks a role from the Material 3 dropdown: tap to open, tap the entry.
  Future<void> chooseRole(WidgetTester tester, String role) async {
    await tapAndSettle(tester, find.byType(DropdownMenu<String>));
    await tapAndSettle(tester, find.text(role).last);
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String name = "Pranav Ahuja",
    String identifier = "pranav@example.com",
    String password = "supersecret123",
    String? confirm,
    String? role = "Teacher",
  }) async {
    await enterText(tester, fieldWithLabel("Full Name"), name);
    await enterText(
        tester, fieldWithLabel("Email id / Phone Number"), identifier);
    await enterText(tester, fieldWithLabel("Password"), password);
    await enterText(
        tester, fieldWithLabel("Confirm Password"), confirm ?? password);
    if (role != null) await chooseRole(tester, role);
  }

  testWidgets("signup_renders | All four fields and the role dropdown are shown",
      (WidgetTester tester) async {
    await pumpSignUp(tester);

    expect(fieldWithLabel("Full Name"), findsOneWidget);
    expect(fieldWithLabel("Email id / Phone Number"), findsOneWidget);
    expect(fieldWithLabel("Password"), findsOneWidget);
    expect(fieldWithLabel("Confirm Password"), findsOneWidget);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(buttonWithText("Sign up"), findsOneWidget);
  });

  testWidgets("signup_requires_name | A blank name is refused",
      (WidgetTester tester) async {
    await pumpSignUp(tester);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(currentSnackBarText(tester), "Please enter your full name");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("signup_requires_identifier | An email or phone is required",
      (WidgetTester tester) async {
    await pumpSignUp(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(currentSnackBarText(tester),
        "Please enter your email id or phone number");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("signup_requires_long_password | Under eight characters is refused",
      (WidgetTester tester) async {
    // The backend enforces this too, but catching it here saves a round trip
    // and gives the user the message immediately.
    await pumpSignUp(tester);
    await fillForm(tester, password: "short", confirm: "short", role: null);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(currentSnackBarText(tester),
        "Password must be at least 8 characters");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("signup_requires_matching_passwords | A typo is caught",
      (WidgetTester tester) async {
    await pumpSignUp(tester);
    await fillForm(tester, confirm: "supersecret124", role: null);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(currentSnackBarText(tester), "Passwords do not match");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("signup_requires_account_type | Skipping the role is refused",
      (WidgetTester tester) async {
    // The regression that matters most on this screen: accountType used to
    // default to 0, so anybody who ignored the dropdown was silently
    // registered as a teacher.
    await pumpSignUp(tester);
    await fillForm(tester, role: null);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(currentSnackBarText(tester), "Please choose an account type");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("signup_teacher_sends_zero | Teacher maps to account_type 0",
      (WidgetTester tester) async {
    api.stub("/auth/signup", status: 201, body: tokenJson(isNewUser: true));
    await pumpSignUp(tester);
    await fillForm(tester, role: "Teacher");

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(api.requestTo("/auth/signup").body, {
      "full_name": "Pranav Ahuja",
      "identifier": "pranav@example.com",
      "password": "supersecret123",
      "account_type": 0,
    });
  });

  testWidgets("signup_student_sends_one | Student maps to account_type 1",
      (WidgetTester tester) async {
    api.stub("/auth/signup",
        status: 201,
        body: tokenJson(isNewUser: true, user: studentUserJson()));
    await pumpSignUp(tester);
    await fillForm(tester, role: "Student");

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(api.requestTo("/auth/signup").body["account_type"], 1);
  });

  testWidgets("signup_trims_input | Stray spaces do not reach the server",
      (WidgetTester tester) async {
    api.stub("/auth/signup", status: 201, body: tokenJson(isNewUser: true));
    await pumpSignUp(tester);
    await fillForm(
      tester,
      name: "  Pranav Ahuja  ",
      identifier: "  pranav@example.com  ",
    );

    await tapAndSettle(tester, buttonWithText("Sign up"));

    final RecordedRequest sent = api.requestTo("/auth/signup");
    expect(sent.body["full_name"], "Pranav Ahuja");
    expect(sent.body["identifier"], "pranav@example.com");
  });

  testWidgets("signup_accepts_a_phone_identifier | One field takes either",
      (WidgetTester tester) async {
    // The server decides whether it received an email or a phone, so the app
    // must pass the single field straight through without guessing.
    api.stub("/auth/signup", status: 201, body: tokenJson(isNewUser: true));
    await pumpSignUp(tester);
    await fillForm(tester, identifier: "+919876543210");

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(api.requestTo("/auth/signup").body["identifier"], "+919876543210");
  });

  testWidgets("signup_success_opens_dashboard | A chosen role skips the profile screen",
      (WidgetTester tester) async {
    api.stub("/auth/signup", status: 201, body: tokenJson(isNewUser: true));
    await pumpSignUp(tester);
    await fillForm(tester);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(find.byType(GB_Dashboard), findsOneWidget);
  });

  testWidgets("signup_shows_server_error | A duplicate account is reported",
      (WidgetTester tester) async {
    api.stubError("/auth/signup",
        status: 409, detail: "An account with that email already exists");
    await pumpSignUp(tester);
    await fillForm(tester);

    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(currentSnackBarText(tester),
        "An account with that email already exists");
    expect(find.byType(GB_SignUp), findsOneWidget);
  });

  testWidgets("signup_passwords_start_hidden | Both password fields are obscured",
      (WidgetTester tester) async {
    await pumpSignUp(tester);

    expect(isObscured(tester, "Password"), isTrue);
    expect(isObscured(tester, "Confirm Password"), isTrue);
  });

  testWidgets("signup_visibility_matches_login | The icon means the same thing here",
      (WidgetTester tester) async {
    // Sign-up and Login once pointed this icon opposite ways for the same
    // state, so the two screens are pinned to the same convention.
    await pumpSignUp(tester);
    expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));

    await tapAndSettle(tester, find.byIcon(Icons.visibility_off).first);

    expect(isObscured(tester, "Password"), isFalse);
    expect(isObscured(tester, "Confirm Password"), isTrue);
  });

  testWidgets("signup_disables_button_while_submitting | No double submissions",
      (WidgetTester tester) async {
    api.stub("/auth/signup",
        status: 201,
        body: tokenJson(),
        delay: const Duration(milliseconds: 400));
    await pumpSignUp(tester);
    await fillForm(tester);

    await tester.tap(buttonWithText("Sign up"));
    await tester.pump();

    expect(buttonWithText("Creating account..."), findsOneWidget);
    expect(isButtonDisabled(tester, "Creating account..."), isTrue);

    await pumpFrames(tester, times: 8);
  });

  testWidgets("signup_to_login | The link back to login works",
      (WidgetTester tester) async {
    await pumpSignUp(tester);

    await tapAndSettle(tester, find.text("Already have an account? Login here"));

    expect(find.byType(GB_Login), findsOneWidget);
  });

  testWidgets("signup_to_mobile_login | The phone button opens OTP login",
      (WidgetTester tester) async {
    await pumpSignUp(tester);

    await tapAndSettle(tester, find.byType(ElevatedButton).last);

    expect(find.byType(GB_MobileLogin), findsOneWidget);
  });
}
