/// The "who are you?" screen that Google and phone sign-ins land on, because
/// neither can tell the backend teacher from student.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/mock_api.dart';

void main() {
  late FakeApi api;

  setUp(() {
    api = startTest();
    // Reaching this screen always means an account already exists on the
    // backend: the OTP or Google call created it before routing here.
    signInAs(needsRoleUserJson());
  });
  tearDown(endTest);

  Future<void> pumpProfile(WidgetTester tester, {bool isNewUser = true}) =>
      pumpScreen(tester, GB_CompleteProfile(isNewUser: isNewUser));

  testWidgets("profile_renders | A name field and both role tiles are shown",
      (WidgetTester tester) async {
    await pumpProfile(tester);

    expect(fieldWithLabel("Full Name"), findsOneWidget);
    expect(find.text("Teacher"), findsOneWidget);
    expect(find.text("Student"), findsOneWidget);
    expect(buttonWithText("Continue"), findsOneWidget);
  });

  testWidgets("profile_new_user_wording | A first sign-in is welcomed",
      (WidgetTester tester) async {
    // isNewUser only picks the wording; the routing decision is
    // needsAccountType, which is a different question.
    await pumpProfile(tester, isNewUser: true);

    expect(find.text("Welcome!"), findsOneWidget);
    expect(find.text("Welcome to Grow Buddy!"), findsOneWidget);
  });

  testWidgets("profile_returning_user_wording | A returning user is told to finish",
      (WidgetTester tester) async {
    // Somebody who abandoned this screen is no longer new, but still has no
    // role, so they come back here with different wording.
    await pumpProfile(tester, isNewUser: false);

    expect(find.text("Finish setting up"), findsOneWidget);
    expect(find.text("Finish setting up your account"), findsOneWidget);
  });

  testWidgets("profile_hides_placeholder_name | The stand-in name is not prefilled",
      (WidgetTester tester) async {
    // Phone sign-ups are stored as "GrowBuddy User". Prefilling that would
    // invite the user to accept it as their name.
    await pumpProfile(tester);

    expect(fieldText(tester, "Full Name"), isEmpty);
  });

  testWidgets("profile_prefills_a_real_name | A name from Google is kept",
      (WidgetTester tester) async {
    signInAs(userJson(
      fullName: "Pranav Ahuja",
      accountType: null,
      role: null,
      needsAccountType: true,
    ));

    await pumpProfile(tester);

    expect(fieldText(tester, "Full Name"), "Pranav Ahuja");
  });

  testWidgets("profile_requires_a_name | A blank name is refused",
      (WidgetTester tester) async {
    await pumpProfile(tester);

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(currentSnackBarText(tester), "Please enter your full name");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("profile_requires_a_role | Continuing without a choice is refused",
      (WidgetTester tester) async {
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(currentSnackBarText(tester),
        "Please choose whether you're a teacher or a student");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("profile_teacher_patches_zero | Teacher sends account_type 0",
      (WidgetTester tester) async {
    api.stub("/auth/me", body: userJson(), method: "PATCH");
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav Ahuja");
    await tapAndSettle(tester, find.text("Teacher"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    final RecordedRequest sent = api.requestTo("/auth/me");
    expect(sent.method, "PATCH");
    expect(sent.body, {"full_name": "Pranav Ahuja", "account_type": 0});
  });

  testWidgets("profile_student_patches_one | Student sends account_type 1",
      (WidgetTester tester) async {
    api.stub("/auth/me", body: studentUserJson(), method: "PATCH");
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Aarav");
    await tapAndSettle(tester, find.text("Student"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(api.requestTo("/auth/me").body["account_type"], 1);
  });

  testWidgets("profile_sends_the_stored_token | The PATCH is authenticated",
      (WidgetTester tester) async {
    api.stub("/auth/me", body: userJson(), method: "PATCH");
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");
    await tapAndSettle(tester, find.text("Teacher"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(api.requestTo("/auth/me").bearerToken, kTestTokenValue);
  });

  testWidgets("profile_success_opens_dashboard | A completed profile moves on",
      (WidgetTester tester) async {
    api.stub("/auth/me", body: userJson(), method: "PATCH");
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");
    await tapAndSettle(tester, find.text("Teacher"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(find.byType(GB_Dashboard), findsOneWidget);
    expect(find.byType(GB_CompleteProfile), findsNothing);
  });

  testWidgets("profile_updates_the_session | The new role reaches the dashboard",
      (WidgetTester tester) async {
    // Skipping this would leave gCurrentUser roleless, and the dashboard would
    // fall through to the student screen for a teacher who just said otherwise.
    api.stub("/auth/me", body: userJson(), method: "PATCH");
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");
    await tapAndSettle(tester, find.text("Teacher"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(gCurrentUser!.role, "teacher");
    expect(gCurrentUser!.needsAccountType, isFalse);
    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });

  testWidgets("profile_shows_server_error | A rejected PATCH is reported",
      (WidgetTester tester) async {
    api.stubError("/auth/me",
        status: 422, detail: "account_type must be 0 (teacher) or 1 (student)");
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");
    await tapAndSettle(tester, find.text("Teacher"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(currentSnackBarText(tester),
        "account_type must be 0 (teacher) or 1 (student)");
    expect(find.byType(GB_CompleteProfile), findsOneWidget);
  });

  testWidgets("profile_needs_a_session | A missing token stops before the call",
      (WidgetTester tester) async {
    gLoginToken = null;
    await pumpProfile(tester);
    await enterText(tester, fieldWithLabel("Full Name"), "Pranav");
    await tapAndSettle(tester, find.text("Teacher"));

    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(currentSnackBarText(tester),
        "Your session expired. Please sign in again.");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("profile_leave_asks_first | The back arrow confirms before signing out",
      (WidgetTester tester) async {
    // The arrow looks like ordinary back navigation, but there is nothing to
    // pop to and the only way off this screen is to end the session.
    await pumpProfile(tester);

    await tapAndSettle(tester, find.byTooltip("Use a different account"));

    expect(find.text("Use a different account?"), findsOneWidget);
    expect(find.text("Stay here"), findsOneWidget);
    expect(find.text("Sign out"), findsOneWidget);
  });

  testWidgets("profile_leave_can_be_cancelled | Staying keeps the session",
      (WidgetTester tester) async {
    await pumpProfile(tester);
    await tapAndSettle(tester, find.byTooltip("Use a different account"));

    await tapAndSettle(tester, find.text("Stay here"));

    expect(find.byType(GB_CompleteProfile), findsOneWidget);
    expect(gLoginToken, isNotNull);
  });

  testWidgets("profile_leave_signs_out | Confirming clears the session",
      (WidgetTester tester) async {
    await pumpProfile(tester);
    await tapAndSettle(tester, find.byTooltip("Use a different account"));

    await tapAndSettle(tester, find.text("Sign out"));

    expect(gLoginToken, isNull);
    expect(gCurrentUser, isNull);
    expect(find.byType(GB_Login), findsOneWidget);
  });
}
