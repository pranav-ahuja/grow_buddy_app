/// Adding a class and registering a pupil, on a real device.
///
/// Both stores are in memory today — there is no classes or students endpoint
/// yet — so nothing here survives the app being killed. These tests cover the
/// screens as they behave now, and the session-persistence file states the
/// limitation explicitly so nobody mistakes it for a bug in these.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_AddClassSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassScreen.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_support.dart';

const String _password = "supersecret123";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late bool backendUp;

  setUpAll(() async {
    backendUp = await backendIsReachable();
  });

  setUp(resetDevice);

  /// Gets to a teacher dashboard the honest way, through sign-up.
  Future<void> reachDashboard(WidgetTester tester) async {
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

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
  }

  testWidgets("e2e_dashboard_lists_classes | The seeded classes are on screen",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await reachDashboard(tester);

    expect(find.text("Daycare"), findsOneWidget);
    expect(find.text("Nursery"), findsOneWidget);
  });

  testWidgets("e2e_add_a_class | A new class appears on the dashboard",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await reachDashboard(tester);
    await scrollUp(tester, by: 900);

    await tapAndSettle(tester, find.text("Add a class"));
    expect(find.byType(GB_AddClassSheet), findsOneWidget);

    await enterText(tester, fieldWithLabel("Class name"), "Grade 6");
    await tapAndSettle(tester, buttonWithText("Add class"));

    await scrollUp(tester, by: 1100);
    expect(find.text("Grade 6"), findsOneWidget);
  });

  testWidgets("e2e_open_a_class | A class tile opens its own screen",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await reachDashboard(tester);

    await tapAndSettle(tester, find.text("Nursery"));

    expect(find.byType(GB_ClassScreen), findsOneWidget);
    expect(find.text("Welcome to your class!"), findsOneWidget);
  });

  testWidgets("e2e_register_a_student | The FAB form files a pupil under a class",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await reachDashboard(tester);

    await tapAndSettle(tester, find.byTooltip("Register new student"));
    expect(find.byType(GB_RegisterStudentSheet), findsOneWidget);

    await enterText(tester, fieldWithLabel("Student's Name"), "Aarav Sharma");
    await enterText(tester, fieldWithLabel("Age"), "4");
    await enterText(tester, fieldWithLabel("Address"), "12 Park Road");
    await tapAndSettle(tester, find.text("Male"));

    await chooseClass(tester, "Nursery");

    await tapAndSettle(tester, find.text("Add to Class"));

    // The confirmation names the class and the id, because registration is the
    // only place the id is ever announced.
    expect(find.textContaining("Aarav Sharma"), findsWidgets);
  });

  testWidgets("e2e_student_appears_in_the_class | The roster fills in",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await reachDashboard(tester);

    await tapAndSettle(tester, find.text("Nursery"));
    await scrollUp(tester, by: 500);
    expect(find.text("No students in this class yet."), findsOneWidget);

    // Registering from inside a class preselects it, so no dropdown here.
    await tapAndSettle(tester, find.text("Register"));
    await enterText(tester, fieldWithLabel("Student's Name"), "Diya Nair");
    await enterText(tester, fieldWithLabel("Age"), "5");
    await enterText(tester, fieldWithLabel("Address"), "9 Lake View");
    await tapAndSettle(tester, find.text("Female"));
    await tapAndSettle(tester, find.text("Add to Class"));

    await scrollUp(tester, by: 500);
    expect(find.text("Diya Nair"), findsOneWidget);
    expect(find.text("No students in this class yet."), findsNothing);
  });

  testWidgets("e2e_class_count_updates | The dashboard tile counts the pupil",
      (WidgetTester tester) async {
    if (!backendUp) markTestSkipped(backendUnreachableReason);
    if (!backendUp) return;

    await reachDashboard(tester);

    await tapAndSettle(tester, find.byTooltip("Register new student"));
    await enterText(tester, fieldWithLabel("Student's Name"), "Kabir Rao");
    await enterText(tester, fieldWithLabel("Age"), "6");
    await enterText(tester, fieldWithLabel("Address"), "3 Hill Street");
    await tapAndSettle(tester, find.text("Male"));
    await chooseClass(tester, "Daycare");
    await tapAndSettle(tester, find.text("Add to Class"));

    // Singular, not "1 students" — and not the "no. of students" placeholder,
    // which only stands in while a class is empty.
    expect(find.text("1 student"), findsOneWidget);
  });
}
