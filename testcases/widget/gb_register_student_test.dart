/// The register-student sheet: the longest form in the app, and the only one
/// with a validator on nearly every field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';

import '../support/harness.dart';

void main() {
  setUp(startTest);
  tearDown(endTest);

  late GB_Student? returned;
  late bool closed;

  Future<void> openSheet(WidgetTester tester, {int? initialClassId}) async {
    returned = null;
    closed = false;

    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                returned = await GB_RegisterStudentSheet.show(
                  context,
                  initialClassId: initialClassId,
                );
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

  /// Fills only what the form insists on.
  Future<void> fillRequired(
    WidgetTester tester, {
    String name = "Aarav Sharma",
    String age = "4",
    String address = "12 Park Road",
    String gender = "Male",
  }) async {
    await enterText(tester, fieldWithLabel("Student's Name"), name);
    await enterText(tester, fieldWithLabel("Age"), age);
    await enterText(tester, fieldWithLabel("Address"), address);
    await tapAndSettle(tester, find.text(gender));
  }

  Future<void> submit(WidgetTester tester) async {
    await tapAndSettle(tester, find.text("Add to Class"));
  }

  testWidgets("student_form_renders | The required fields are all present",
      (WidgetTester tester) async {
    await openSheet(tester);

    expect(fieldWithLabel("Student's Name"), findsOneWidget);
    expect(fieldWithLabel("Age"), findsOneWidget);
    expect(fieldWithLabel("Address"), findsOneWidget);
    expect(find.text("Male"), findsOneWidget);
    expect(find.text("Female"), findsOneWidget);
    expect(find.text("Add to Class"), findsOneWidget);
  });

  testWidgets("student_form_requires_everything | An empty form is refused",
      (WidgetTester tester) async {
    await openSheet(tester);

    await submit(tester);

    expect(find.text("Enter the student's name"), findsOneWidget);
    expect(find.text("Enter the age"), findsOneWidget);
    expect(find.text("Enter the address"), findsOneWidget);
    expect(find.text("Select a gender"), findsOneWidget);
    expect(GB_StudentStore.students.value, isEmpty);
  });

  testWidgets("student_form_reports_every_problem_at_once | Nothing is held back",
      (WidgetTester tester) async {
    // The gender check and the field validators both run before either is
    // acted on, so the teacher is not sent round a second time.
    await openSheet(tester);
    await enterText(tester, fieldWithLabel("Student's Name"), "Aarav");

    await submit(tester);

    expect(find.text("Enter the age"), findsOneWidget);
    expect(find.text("Select a gender"), findsOneWidget);
  });

  testWidgets("student_form_age_takes_digits_only | Letters never reach the field",
      (WidgetTester tester) async {
    // The field carries a digitsOnly input formatter, so the "Use numbers
    // only" validator branch is unreachable from the UI — the keystrokes are
    // dropped first. Asserting on the behaviour the user actually gets rather
    // than on the message they can never see.
    await openSheet(tester);
    await fillRequired(tester, age: "four");

    expect(fieldText(tester, "Age"), isEmpty);

    await submit(tester);

    expect(find.text("Enter the age"), findsOneWidget);
    expect(GB_StudentStore.students.value, isEmpty);
  });

  testWidgets("student_form_age_strips_stray_letters | Digits survive, letters do not",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester, age: "4a");

    expect(fieldText(tester, "Age"), "4");
  });

  testWidgets("student_form_rejects_an_impossible_age | 202 is a typo, not a pupil",
      (WidgetTester tester) async {
    // Letting it through would print "Age 202" on the class screen's card.
    await openSheet(tester);
    await fillRequired(tester, age: "202");

    await submit(tester);

    expect(find.text("Enter an age between 1 and 30"), findsOneWidget);
  });

  testWidgets("student_form_rejects_age_zero | The range starts at one",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester, age: "0");

    await submit(tester);

    expect(find.text("Enter an age between 1 and 30"), findsOneWidget);
  });

  testWidgets("student_form_accepts_the_minimum | Name, age, gender, address",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(GB_StudentStore.students.value, hasLength(1));
    expect(returned!.name, "Aarav Sharma");
    expect(returned!.gender, "Male");
  });

  testWidgets("student_form_assigns_an_id | Registration hands out GB-0001",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(returned!.studentId, "GB-0001");
  });

  testWidgets("student_form_closes_on_success | The sheet goes away",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(closed, isTrue);
    expect(find.byType(GB_RegisterStudentSheet), findsNothing);
  });

  testWidgets("student_form_contacts_are_optional | A blank guardian is stored as null",
      (WidgetTester tester) async {
    // Storing a contact made of empty strings would render an empty "Mother"
    // row on the student's profile.
    await openSheet(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(returned!.mother, isNull);
    expect(returned!.father, isNull);
    expect(returned!.guardian, isNull);
  });

  testWidgets("student_form_rejects_a_short_mobile | Four digits is not a number",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);
    await enterText(tester, fieldWithLabel("Guardian's Mobile"), "1234");

    await submit(tester);

    expect(find.text("Enter a valid mobile number"), findsOneWidget);
    expect(GB_StudentStore.students.value, isEmpty);
  });

  testWidgets("student_form_accepts_a_formatted_mobile | Spaces and dashes are fine",
      (WidgetTester tester) async {
    // Numbers arrive with spaces, dashes, and country codes; a stricter check
    // would reject perfectly good ones.
    await openSheet(tester);
    await fillRequired(tester);
    await enterText(
        tester, fieldWithLabel("Guardian's Mobile"), "+91 98765-43210");

    await submit(tester);

    expect(GB_StudentStore.students.value, hasLength(1));
  });

  testWidgets("student_form_rejects_a_malformed_email | An address needs an @",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);
    // Mother and father each have an "Email" box, so the finder has to say
    // which one. The first is the mother's.
    await enterText(tester, fieldWithLabel("Email").first, "not-an-email");

    await submit(tester);

    expect(find.text("Enter a valid email address"), findsOneWidget);
  });

  testWidgets("student_form_accepts_a_good_email | A real address passes",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);
    await enterText(
        tester, fieldWithLabel("Email").first, "parent@example.com");

    await submit(tester);

    expect(GB_StudentStore.students.value, hasLength(1));
    expect(returned!.mother!.email, "parent@example.com");
  });

  testWidgets("student_form_lists_the_classes | The dropdown offers real classes",
      (WidgetTester tester) async {
    // A dropdown rather than free text: typing "nursery" would create a
    // student that nothing could file under the actual Nursery class.
    await openSheet(tester);

    await tapAndSettle(tester, find.byType(DropdownButtonFormField<int?>));

    expect(find.text("Nursery").last, findsOneWidget);
    expect(find.text("Not assigned").last, findsOneWidget);
  });

  testWidgets("student_form_honours_the_initial_class | Opened from a class, filed there",
      (WidgetTester tester) async {
    await openSheet(tester, initialClassId: 3);
    await fillRequired(tester);

    await submit(tester);

    expect(returned!.classId, 3);
    expect(GB_StudentStore.countInClass(3), 1);
  });

  testWidgets("student_form_allows_no_class | A student can be registered unfiled",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(returned!.classId, isNull);
  });

  testWidgets("student_form_dismissal_returns_null | Backing out registers nobody",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(tester);

    await tester.tapAt(const Offset(215, 20));
    await pumpFrames(tester, times: 10);

    expect(returned, isNull);
    expect(GB_StudentStore.students.value, isEmpty);
  });

  testWidgets("student_form_trims_what_it_stores | Stray spaces do not persist",
      (WidgetTester tester) async {
    await openSheet(tester);
    await fillRequired(
      tester,
      name: "  Aarav Sharma  ",
      address: "  12 Park Road  ",
    );

    await submit(tester);

    expect(returned!.name, "Aarav Sharma");
    expect(returned!.address, "12 Park Road");
  });
}
