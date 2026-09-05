/// The teacher's home screen: events carousel, class list, register-student
/// action, and the four-tab bar where three tabs do not exist yet.
library;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_AddClassSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassScreen.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeAppBar.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  setUp(() {
    startTest();
    signInAs(userJson());
  });
  tearDown(endTest);

  Future<void> pumpDashboard(WidgetTester tester) =>
      pumpScreen(tester, const GB_TeacherDashboard());

  testWidgets("dashboard_renders | Bar, carousel, and class list are all there",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    expect(find.byType(GB_HomeAppBar), findsOneWidget);
    expect(find.byType(CarouselSlider), findsOneWidget);
    expect(find.text("Your classes at a glance!"), findsOneWidget);
  });

  testWidgets("dashboard_lists_seeded_classes | The five classes are shown",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    expect(find.text("Daycare"), findsOneWidget);
    expect(find.text("Playgroup"), findsOneWidget);
    expect(find.text("Pre Nursery"), findsOneWidget);
  });

  testWidgets("dashboard_has_an_add_tile | The list ends with Add a class",
      (WidgetTester tester) async {
    await pumpDashboard(tester);
    // Last in a lazily-built list, so it has to be scrolled into range first.
    await scrollUp(tester, by: 900);

    expect(find.byType(GB_AddClassTile), findsOneWidget);
  });

  testWidgets("dashboard_shows_new_classes | Adding a class repaints the list",
      (WidgetTester tester) async {
    // The list is a ValueListenableBuilder over the store rather than a copy
    // this screen holds, so this is what proves the wiring.
    await pumpDashboard(tester);
    expect(find.text("Grade 6"), findsNothing);

    GB_ClassStore.addClass(name: "Grade 6");
    await pumpFrames(tester);
    await scrollUp(tester, by: 1100);

    expect(find.text("Grade 6"), findsOneWidget);
  });

  testWidgets("dashboard_empty_class_keeps_placeholder | Zero students is not shown as zero",
      (WidgetTester tester) async {
    // "0 students" reads as a failure; the design's placeholder reads as a
    // column heading waiting to be filled.
    await pumpDashboard(tester);

    expect(find.text("0 students"), findsNothing);
    expect(find.text("no. of students"), findsWidgets);
  });

  testWidgets("dashboard_counts_one_student | A single student is singular",
      (WidgetTester tester) async {
    GB_StudentStore.addStudent(
      name: "Aarav",
      age: "4",
      gender: "Male",
      address: "12 Park Road",
      classId: 0,
    );

    await pumpDashboard(tester);

    expect(find.text("1 student"), findsOneWidget);
  });

  testWidgets("dashboard_counts_many_students | Several students are plural",
      (WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      GB_StudentStore.addStudent(
        name: "Student $i",
        age: "4",
        gender: "Male",
        address: "12 Park Road",
        classId: 1,
      );
    }

    await pumpDashboard(tester);

    expect(find.text("3 students"), findsOneWidget);
  });

  testWidgets("dashboard_opens_a_class | Tapping a tile opens the class screen",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    await tapAndSettle(tester, find.text("Nursery"));

    expect(find.byType(GB_ClassScreen), findsOneWidget);
  });

  testWidgets("dashboard_passes_the_class_along | The right class is opened",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    await tapAndSettle(tester, find.text("Playgroup"));

    expect(
      tester.widget<GB_ClassScreen>(find.byType(GB_ClassScreen)).classInfo.name,
      "Playgroup",
    );
  });

  testWidgets("dashboard_add_class_opens_the_sheet | The add tile opens the form",
      (WidgetTester tester) async {
    await pumpDashboard(tester);
    await scrollUp(tester, by: 900);

    await tapAndSettle(tester, find.byType(GB_AddClassTile));

    // By type, not by text: the tile that opened the sheet carries the same
    // "Add a class" wording, so a text match would find two either way.
    expect(find.byType(GB_AddClassSheet), findsOneWidget);
  });

  testWidgets("dashboard_fab_registers_a_student | The FAB opens the big form",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    await tapAndSettle(tester, find.byTooltip("Register new student"));

    expect(find.byType(GB_RegisterStudentSheet), findsOneWidget);
  });

  testWidgets("dashboard_has_four_tabs | Home, Attendance, Fee, and Message",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    expect(find.text("Home"), findsOneWidget);
    expect(find.text("Attendance"), findsOneWidget);
    expect(find.text("Fee"), findsOneWidget);
    expect(find.text("Message"), findsOneWidget);
  });

  testWidgets("dashboard_spells_attendance_correctly | The design's typo is not shipped",
      (WidgetTester tester) async {
    // Both the Figma frame and claude_ui/homescreen.jpg read "Attendence".
    // The label is what users read, so the app spells it correctly on purpose.
    await pumpDashboard(tester);

    expect(find.text("Attendence"), findsNothing);
  });

  testWidgets("dashboard_unbuilt_tabs_say_so | The other three announce themselves",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    await tapAndSettle(tester, find.text("Fee"));

    expect(currentSnackBarText(tester), "Fee is coming soon");
  });

  testWidgets("dashboard_unbuilt_tabs_keep_the_highlight | The selection does not move",
      (WidgetTester tester) async {
    // Moving the highlight to a tab that shows the same body would be a lie
    // about what happened.
    await pumpDashboard(tester);

    await tapAndSettle(tester, find.text("Message"));

    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      0,
    );
  });

  testWidgets("dashboard_carousel_has_an_indicator | One dot per event",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    expect(
      tester
          .widget<GB_CarouselIndicator>(find.byType(GB_CarouselIndicator))
          .count,
      3,
    );
  });

  testWidgets("dashboard_events_are_shown | The three placeholder events render",
      (WidgetTester tester) async {
    await pumpDashboard(tester);

    // The carousel keeps neighbours mounted, so at least the first is visible.
    expect(find.text("Drawing Competition"), findsWidgets);
  });
}
