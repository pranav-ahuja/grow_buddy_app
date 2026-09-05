/// Sign up, sign out, sign back in — against the real backend.
///
/// The widget suite proves the app sends the right JSON. This proves the
/// backend accepts it, mints a token the app can use, and remembers the account
/// well enough to log into a minute later.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';

import 'e2e_support.dart';

const String _password = "supersecret123";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late bool backendUp;

  setUpAll(() async {
    backendUp = await backendIsReachable();
  });

  setUp(resetDevice);

  /// Walks onboarding to the sign-up form and registers [email] as a teacher.
  Future<void> signUpAsTeacher(WidgetTester tester, String email) async {
    await launchApp(tester);
    await tapAndSettle(tester, find.byType(FloatingActionButton));
    await tapAndSettle(tester, buttonWithText("Sign up"));

    expect(find.byType(GB_SignUp), findsOneWidget);

    await enterText(tester, fieldWithLabel("Full Name"), "Tastu Teacher");
    await enterText(tester, fieldWithLabel("Email id / Phone Number"), email);
    await enterText(tester, fieldWithLabel("Password"), _password);
    await enterText(tester, fieldWithLabel("Confirm Password"), _password);

    await chooseFromDropdownMenu(tester, "Teacher");

    await tapAndSettle(tester, buttonWithText("Sign up"));
  }

  testWidgets("e2e_signup_reaches_the_dashboard | A new teacher lands on their classes",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await signUpAsTeacher(tester, uniqueEmail());

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
    expect(find.text("Your classes at a glance!"), findsOneWidget);
  });

  testWidgets("e2e_signup_stores_a_real_token | The JWT survives to the dashboard",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await signUpAsTeacher(tester, uniqueEmail());

    // A real JWT, not the stub the widget suite uses: three dot-separated
    // segments, and long enough to be carrying claims.
    expect(gLoginToken, isNotNull);
    expect(gLoginToken!.split(".").length, 3);
    expect(gCurrentUser!.role, "teacher");
  });

  testWidgets("e2e_signup_then_login | An account can be signed back into",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    final String email = uniqueEmail();
    await signUpAsTeacher(tester, email);
    expect(find.byType(GB_TeacherDashboard), findsOneWidget);

    // Log out through the profile menu, the way a user would.
    await tapAndSettle(tester, find.byTooltip("Profile"));
    await tapAndSettle(tester, find.text("Logout"));
    expect(find.byType(GB_Login), findsOneWidget);
    expect(gLoginToken, isNull);

    await enterText(tester, fieldWithLabel("Email"), email);
    await enterText(tester, fieldWithLabel("Password"), _password);
    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });

  testWidgets("e2e_login_rejects_a_wrong_password | The server says so, and the app shows it",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    final String email = uniqueEmail();
    await signUpAsTeacher(tester, email);
    await tapAndSettle(tester, find.byTooltip("Profile"));
    await tapAndSettle(tester, find.text("Logout"));

    await enterText(tester, fieldWithLabel("Email"), email);
    await enterText(tester, fieldWithLabel("Password"), "definitely-wrong");
    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.text("Invalid email or password"), findsOneWidget);
    expect(find.byType(GB_Login), findsOneWidget);
    expect(gLoginToken, isNull);
  });

  testWidgets("e2e_signup_rejects_a_duplicate | The same email cannot register twice",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    final String email = uniqueEmail();
    await signUpAsTeacher(tester, email);

    await resetDevice();
    await signUpAsTeacher(tester, email);

    // The 409 comes back as a sentence the app shows verbatim.
    expect(find.byType(GB_SignUp), findsOneWidget);
    expect(find.byType(GB_TeacherDashboard), findsNothing);
  });

  testWidgets("e2e_login_is_case_insensitive | Capitalised email still works",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    final String email = uniqueEmail();
    await signUpAsTeacher(tester, email);
    await tapAndSettle(tester, find.byTooltip("Profile"));
    await tapAndSettle(tester, find.text("Logout"));

    await enterText(tester, fieldWithLabel("Email"), email.toUpperCase());
    await enterText(tester, fieldWithLabel("Password"), _password);
    await tapAndSettle(tester, buttonWithText("Login"));

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });
}
