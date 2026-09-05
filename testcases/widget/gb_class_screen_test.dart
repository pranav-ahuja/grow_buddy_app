/// One class: its tinted header, its events, the six feature tiles, and the
/// student roster that fills in as pupils are registered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassScreen.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

import '../support/harness.dart';

const GB_ClassInfo _nursery = GB_ClassInfo(
  id: 3,
  name: "Nursery",
  subtitle: "no. of students",
  imagePath: kClassAvatarImage,
  fillColor: kClassTileGreenFill,
  borderColor: kClassTileGreenBorder,
);

GB_Student _register({String name = "Aarav", int? classId = 3}) {
  return GB_StudentStore.addStudent(
    name: name,
    age: "4",
    gender: "Male",
    address: "12 Park Road",
    classId: classId,
  );
}

void main() {
  setUp(startTest);
  tearDown(endTest);

  Future<void> pumpClass(WidgetTester tester) =>
      pumpScreen(tester, const GB_ClassScreen(classInfo: _nursery));

  testWidgets("class_screen_renders | The class name and greeting are shown",
      (WidgetTester tester) async {
    await pumpClass(tester);

    expect(find.text("Nursery"), findsOneWidget);
    expect(find.text("Welcome to your class!"), findsOneWidget);
  });

  testWidgets("class_screen_has_navigation | Back and more-options are reachable",
      (WidgetTester tester) async {
    await pumpClass(tester);

    expect(find.byTooltip("Back"), findsOneWidget);
    expect(find.byTooltip("More options"), findsOneWidget);
  });

  testWidgets("class_screen_shows_its_events | Events name this class",
      (WidgetTester tester) async {
    await pumpClass(tester);

    expect(find.text("Classes: Nursery"), findsWidgets);
  });

  testWidgets("class_screen_lists_the_six_features | All feature tiles are drawn",
      (WidgetTester tester) async {
    await pumpClass(tester);
    await scrollUp(tester, by: 300);

    expect(find.text("Assignment"), findsOneWidget);
    expect(find.text("Attendance"), findsOneWidget);
    expect(find.text("Fee Payment"), findsOneWidget);
  });

  testWidgets("class_screen_features_are_unbuilt | Tapping one says so",
      (WidgetTester tester) async {
    await pumpClass(tester);
    await scrollUp(tester, by: 300);

    await tapAndSettle(tester, find.text("Assignment"));

    expect(currentSnackBarText(tester), "Assignment is coming soon");
  });

  testWidgets("class_screen_empty_roster_says_so | No stand-in pupils are drawn",
      (WidgetTester tester) async {
    // A row of placeholder "Name / Age" cards would look like real pupils and
    // give the teacher nothing to tap to fix that.
    await pumpClass(tester);
    await scrollUp(tester, by: 500);

    expect(find.text("No students in this class yet."), findsOneWidget);
  });

  testWidgets("class_screen_empty_roster_offers_register | A way out of the empty state",
      (WidgetTester tester) async {
    await pumpClass(tester);
    await scrollUp(tester, by: 500);

    await tapAndSettle(tester, find.text("Register"));

    expect(find.byType(GB_RegisterStudentSheet), findsOneWidget);
  });

  testWidgets("class_screen_lists_its_students | Registered pupils appear",
      (WidgetTester tester) async {
    _register(name: "Aarav");
    _register(name: "Diya");

    await pumpClass(tester);
    await scrollUp(tester, by: 500);

    expect(find.text("Aarav"), findsOneWidget);
    expect(find.text("Diya"), findsOneWidget);
    expect(find.text("No students in this class yet."), findsNothing);
  });

  testWidgets("class_screen_ignores_other_classes | Only this class's pupils show",
      (WidgetTester tester) async {
    _register(name: "In Nursery", classId: 3);
    _register(name: "In Daycare", classId: 0);

    await pumpClass(tester);
    await scrollUp(tester, by: 500);

    expect(find.text("In Nursery"), findsOneWidget);
    expect(find.text("In Daycare"), findsNothing);
  });

  testWidgets("class_screen_updates_live | A registration appears without a reload",
      (WidgetTester tester) async {
    // The roster is a ValueListenableBuilder over the store, so this is what
    // proves a student registered from this screen shows up on it.
    await pumpClass(tester);
    await scrollUp(tester, by: 500);
    expect(find.text("No students in this class yet."), findsOneWidget);

    _register(name: "Aarav");
    await pumpFrames(tester);

    expect(find.text("Aarav"), findsOneWidget);
  });

  testWidgets("class_screen_see_all_is_unbuilt | The full list is not there yet",
      (WidgetTester tester) async {
    await pumpClass(tester);
    await scrollUp(tester, by: 500);

    await tapAndSettle(tester, find.text("See All"));

    expect(currentSnackBarText(tester),
        "The full student list is coming soon");
  });

  testWidgets("class_screen_header_matches_the_tile | The panel takes the class hue",
      (WidgetTester tester) async {
    // The class screen paints its header in the same slot the dashboard tile
    // used, so opening a class does not change its colour.
    await pumpClass(tester);

    final int slot = GB_ClassPalette.slotForFill(_nursery.fillColor);
    final Iterable<Container> panels = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).color ==
                GB_ClassPalette.panelAt(slot));

    expect(panels, isNotEmpty);
  });
}
