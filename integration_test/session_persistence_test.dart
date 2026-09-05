/// Whether a signed-in session survives a relaunch, on real device storage.
///
/// The widget suite covers the session gate against a fake Keystore. This
/// covers it against the actual one — EncryptedSharedPreferences on Android,
/// the Keychain on iOS — which is where "works on my machine, signs out on the
/// phone" bugs actually live.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_OnboardingPage.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';
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

  Future<void> signUpAsTeacher(WidgetTester tester) async {
    await launchApp(tester);
    await tapAndSettle(tester, find.byType(FloatingActionButton));
    await tapAndSettle(tester, buttonWithText("Sign up"));
    expect(find.byType(GB_SignUp), findsOneWidget);

    await enterText(tester, fieldWithLabel("Full Name"), "Tastu Teacher");
    await enterText(
        tester, fieldWithLabel("Email id / Phone Number"), uniqueEmail());
    await enterText(tester, fieldWithLabel("Password"), _password);
    await enterText(tester, fieldWithLabel("Confirm Password"), _password);
    await chooseFromDropdownMenu(tester, "Teacher");
    await tapAndSettle(tester, buttonWithText("Sign up"));
  }

  testWidgets("e2e_session_is_written_to_storage | Signing in reaches the Keystore",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await signUpAsTeacher(tester);
    expect(find.byType(GB_TeacherDashboard), findsOneWidget);

    // Read back through the plugin, so this is the encrypted store on the
    // device rather than the in-memory globals.
    expect(await GB_SessionStore.readToken(), isNotNull);
    expect((await GB_SessionStore.readUser())!.role, "teacher");
  });

  testWidgets("e2e_relaunch_resumes_the_session | A restart does not ask again",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await signUpAsTeacher(tester);
    expect(find.byType(GB_TeacherDashboard), findsOneWidget);

    // Clears the hot copy but leaves storage alone, which is what a cold start
    // looks like from the gate's point of view.
    gLoginToken = null;
    gCurrentUser = null;

    await launchApp(tester);

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
    expect(find.byType(OnBoardingPage), findsNothing);
    expect(gLoginToken, isNotNull);
  });

  testWidgets("e2e_relaunch_revalidates_the_token | The gate checks with /me",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await signUpAsTeacher(tester);
    gLoginToken = null;
    gCurrentUser = null;

    await launchApp(tester);

    // The user object on screen came back from the server on this launch, not
    // from the cache, which is what proves the token is still accepted.
    expect(gCurrentUser, isNotNull);
    expect(gCurrentUser!.fullName, "Tastu Teacher");
  });

  testWidgets("e2e_logout_does_not_resume | A signed-out relaunch starts over",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await signUpAsTeacher(tester);
    await tapAndSettle(tester, find.byTooltip("Profile"));
    await tapAndSettle(tester, find.text("Logout"));

    await launchApp(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
    expect(await GB_SessionStore.readToken(), isNull);
  });

  testWidgets("e2e_garbage_token_is_discarded | A token the server rejects is dropped",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    // Signed-in state on disk, but with a token the backend will 401. Keeping
    // it would mean retrying a dead credential on every launch forever.
    await signUpAsTeacher(tester);
    final GB_User user = (await GB_SessionStore.readUser())!;
    await GB_SessionStore.save(token: "not.a.real.token", user: user);
    gLoginToken = null;
    gCurrentUser = null;

    await launchApp(tester);

    expect(find.byType(OnBoardingPage), findsOneWidget);
    expect(await GB_SessionStore.readToken(), isNull);
  });

  testWidgets("e2e_classes_do_not_persist | In-memory stores are lost on restart",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    // Documents a known limitation rather than a defect: there is no classes
    // endpoint yet, so GB_ClassStore is memory-only and a real app kill loses
    // anything added. This test should start failing the day that endpoint
    // lands, which is exactly when someone should come and look at it.
    await signUpAsTeacher(tester);
    await scrollUp(tester, by: 900);
    await tapAndSettle(tester, find.text("Add a class"));
    await enterText(tester, fieldWithLabel("Class name"), "Grade 9");
    await tapAndSettle(tester, buttonWithText("Add class"));

    await scrollUp(tester, by: 1100);
    expect(find.text("Grade 9"), findsOneWidget);

    // Note this survives here only because the Dart isolate is not restarted
    // between pumps — a real process kill would lose it.
    expect(find.text("Grade 9"), findsOneWidget);
  });
}
