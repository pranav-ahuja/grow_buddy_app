/// GB_Dashboard owns no UI: it reads the signed-in role and shows the matching
/// screen. Every auth path funnels through it, so a wrong branch here sends a
/// teacher to a placeholder.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_StudentDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  setUp(startTest);
  tearDown(endTest);

  testWidgets("route_teacher_role | role teacher opens the teacher dashboard",
      (WidgetTester tester) async {
    signInAs(userJson(role: "teacher", accountType: 0));

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });

  testWidgets("route_student_role | role student opens the student dashboard",
      (WidgetTester tester) async {
    signInAs(studentUserJson());

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_StudentDashboard), findsOneWidget);
  });

  testWidgets("route_role_is_case_insensitive | Capitalisation does not matter",
      (WidgetTester tester) async {
    signInAs(userJson(role: "Teacher"));

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });

  testWidgets("route_falls_back_to_account_type | A null role uses the number",
      (WidgetTester tester) async {
    // role stays null until an account type is chosen, so account_type is the
    // fallback rather than a second source of truth.
    signInAs(userJson(role: null, accountType: 0));

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });

  testWidgets("route_empty_role_uses_account_type | An empty string is not a role",
      (WidgetTester tester) async {
    signInAs(userJson(role: "", accountType: 0));

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  });

  testWidgets("route_unknown_user_is_a_student | The safer of the two screens",
      (WidgetTester tester) async {
    // Somebody with neither should have been sent to GB_CompleteProfile before
    // getting here. If one slips through, the student screen shows nothing a
    // teacher-only account could act on.
    signInAs(needsRoleUserJson());

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_StudentDashboard), findsOneWidget);
  });

  testWidgets("route_no_session_is_a_student | A null user does not crash",
      (WidgetTester tester) async {
    gCurrentUser = null;

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.byType(GB_StudentDashboard), findsOneWidget);
  });

  testWidgets("student_dashboard_is_a_placeholder | It says so, by design",
      (WidgetTester tester) async {
    // The student design does not exist yet, so this wording is the branch
    // working as intended rather than a missing screen.
    signInAs(studentUserJson());

    await pumpScreen(tester, const GB_Dashboard());

    expect(find.textContaining("on its way"), findsOneWidget);
  });
}
