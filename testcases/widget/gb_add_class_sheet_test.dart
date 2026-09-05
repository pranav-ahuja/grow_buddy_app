/// The add-a-class bottom sheet, and the duplicate-name rule that keeps the
/// dashboard list readable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_AddClassSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';

import '../support/harness.dart';

void main() {
  setUp(startTest);
  tearDown(endTest);

  /// Opens the sheet the way the dashboard does, and hands back whatever it
  /// returned once it closes.
  late GB_ClassInfo? returned;
  late bool closed;

  Future<void> openSheet(WidgetTester tester) async {
    returned = null;
    closed = false;

    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                returned = await GB_AddClassSheet.show(context);
                closed = true;
              },
              child: const Text("open"),
            ),
          ),
        ),
      ),
    );

    await tapAndSettle(tester, find.text("open"));
  }

  testWidgets("sheet_renders | Title, field, and button are shown",
      (WidgetTester tester) async {
    await openSheet(tester);

    expect(find.byType(GB_AddClassSheet), findsOneWidget);
    expect(fieldWithLabel("Class name"), findsOneWidget);
    expect(buttonWithText("Add class"), findsOneWidget);
  });

  testWidgets("sheet_explains_itself | It says where the class will appear",
      (WidgetTester tester) async {
    await openSheet(tester);

    expect(find.text("It will show up on your dashboard straight away."),
        findsOneWidget);
  });

  testWidgets("sheet_rejects_a_blank_name | An empty field is refused",
      (WidgetTester tester) async {
    await openSheet(tester);

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(find.text("Please enter a class name"), findsOneWidget);
    expect(GB_ClassStore.classes.value, hasLength(5));
  });

  testWidgets("sheet_rejects_whitespace | Spaces alone are not a name",
      (WidgetTester tester) async {
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "   ");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(find.text("Please enter a class name"), findsOneWidget);
    expect(GB_ClassStore.classes.value, hasLength(5));
  });

  testWidgets("sheet_rejects_a_duplicate | Two classes cannot share a name",
      (WidgetTester tester) async {
    // Checked here rather than deduplicated later: two identically named tiles
    // are indistinguishable on the dashboard, so the teacher would have no way
    // to tell which is which.
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "Nursery");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(find.textContaining("already exists"), findsOneWidget);
    expect(GB_ClassStore.classes.value, hasLength(5));
  });

  testWidgets("sheet_duplicate_check_ignores_case | Casing does not dodge it",
      (WidgetTester tester) async {
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "  nursery  ");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(find.textContaining("already exists"), findsOneWidget);
  });

  testWidgets("sheet_error_clears_on_typing | The message goes when you fix it",
      (WidgetTester tester) async {
    // The message is about what was submitted, so it should disappear the
    // moment the teacher starts correcting it rather than sitting there.
    await openSheet(tester);
    await tapAndSettle(tester, buttonWithText("Add class"));
    expect(find.text("Please enter a class name"), findsOneWidget);

    await enterText(tester, fieldWithLabel("Class name"), "G");

    expect(find.text("Please enter a class name"), findsNothing);
  });

  testWidgets("sheet_adds_the_class | A good name reaches the store",
      (WidgetTester tester) async {
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "Grade 1");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(GB_ClassStore.classes.value, hasLength(6));
    expect(GB_ClassStore.nameExists("Grade 1"), isTrue);
  });

  testWidgets("sheet_returns_the_new_class | The caller is handed what it made",
      (WidgetTester tester) async {
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "Grade 2");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(closed, isTrue);
    expect(returned!.name, "Grade 2");
  });

  testWidgets("sheet_trims_the_name | Stray spaces are not stored",
      (WidgetTester tester) async {
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "  Grade 3  ");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(returned!.name, "Grade 3");
  });

  testWidgets("sheet_closes_after_adding | The sheet goes away",
      (WidgetTester tester) async {
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Class name"), "Grade 4");

    await tapAndSettle(tester, buttonWithText("Add class"));

    expect(find.byType(GB_AddClassSheet), findsNothing);
  });

  testWidgets("sheet_dismissal_returns_null | Backing out adds nothing",
      (WidgetTester tester) async {
    // Null is how the dashboard knows not to show its confirmation.
    await openSheet(tester);

    // Tapping the scrim is how a modal sheet is dismissed.
    await tester.tapAt(const Offset(215, 40));
    await pumpFrames(tester, times: 10);

    expect(closed, isTrue);
    expect(returned, isNull);
    expect(GB_ClassStore.classes.value, hasLength(5));
  });
}
