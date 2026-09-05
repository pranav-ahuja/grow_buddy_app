/// The five shared widgets nearly every interactive element in the app is
/// built from. A regression here shows up on a dozen screens at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentFormFields.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_CommonDropDownMenuField.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_FloatingActionButton.dart';

import '../support/harness.dart';

void main() {
  setUp(startTest);
  tearDown(endTest);

  group("GB_buildTextField", () {
    Widget buildField({
      required TextEditingController controller,
      bool obscure = false,
      String label = "Email",
      String hint = "abc@example.com",
      void Function()? onIcon,
    }) {
      return Scaffold(
        body: GB_buildTextField(
          controller: controller,
          suffixIcon: Icons.cancel_outlined,
          iconAction: onIcon ?? () {},
          textFieldHintText: hint,
          textFieldLabel: label,
          textFieldOnChanged: (_) {},
          textFieldKeyboardType: TextInputType.emailAddress,
          textFieldObscureText: obscure,
        ),
      );
    }

    testWidgets("common_field_shows_label_and_hint | Both are drawn",
        (WidgetTester tester) async {
      await pumpScreen(
          tester, buildField(controller: TextEditingController()));

      expect(find.text("Email"), findsOneWidget);
      expect(find.text("abc@example.com"), findsOneWidget);
    });

    testWidgets("common_field_honours_obscure_true | Passing true hides input",
        (WidgetTester tester) async {
      // This helper once carried a dead condition that could never be true, so
      // the passed parameter was effectively ignored. Both directions are
      // pinned here because only checking one would not have caught it.
      await pumpScreen(
        tester,
        buildField(
          controller: TextEditingController(),
          obscure: true,
          label: "Password",
          hint: "",
        ),
      );

      expect(isObscured(tester, "Password"), isTrue);
    });

    testWidgets("common_field_honours_obscure_false | Passing false shows input",
        (WidgetTester tester) async {
      await pumpScreen(
          tester, buildField(controller: TextEditingController()));

      expect(isObscured(tester, "Email"), isFalse);
    });

    testWidgets("common_field_icon_fires | The suffix icon calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        buildField(
          controller: TextEditingController(),
          onIcon: () => taps++,
        ),
      );

      await tapAndSettle(tester, find.byIcon(Icons.cancel_outlined));

      expect(taps, 1);
    });

    testWidgets("common_field_uses_its_controller | Typing reaches the controller",
        (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      await pumpScreen(tester, buildField(controller: controller));

      await enterText(tester, fieldWithLabel("Email"), "typed@example.com");

      expect(controller.text, "typed@example.com");
    });
  });

  group("GB_ElevatedButtonString", () {
    Widget buildButton({String text = "Login", VoidCallback? onPressed}) {
      return Scaffold(
        body: Center(
          child: GB_ElevatedButtonString(
            screenWidth: 400.0,
            horizontalPadding: 0.1,
            verticalPadding: 10.0,
            elevatedButtonText: text,
            buttonColor: kPrimaryColor1,
            elevatedButtonTextColor: kPrimaryColor2,
            elevatedButtonFontWeight: FontWeight.w500,
            elevatedButtonTextSize: kElevatedButtonTextSize,
            onPressed: onPressed,
          ),
        ),
      );
    }

    testWidgets("common_button_shows_its_text | The label is drawn",
        (WidgetTester tester) async {
      await pumpScreen(tester, buildButton(onPressed: () {}));

      expect(find.text("Login"), findsOneWidget);
    });

    testWidgets("common_button_fires | Tapping calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(tester, buildButton(onPressed: () => taps++));

      await tapAndSettle(tester, buttonWithText("Login"));

      expect(taps, 1);
    });

    testWidgets("common_button_null_disables | A null callback disables it",
        (WidgetTester tester) async {
      // How every screen blocks a second submit while one is in flight.
      await pumpScreen(tester, buildButton());

      expect(isButtonDisabled(tester, "Login"), isTrue);
    });
  });

  group("GB_TextButton", () {
    testWidgets("common_text_button_fires | Tapping calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(
            child: GB_TextButton(
              textButtonText: "Forgot Password?",
              textButtonColor: Colors.black54,
              onPressed: () => taps++,
            ),
          ),
        ),
      );

      await tapAndSettle(tester, find.text("Forgot Password?"));

      expect(taps, 1);
    });
  });

  group("DropDownTextFieldMenu", () {
    testWidgets("common_dropdown_offers_both_roles | Teacher and Student",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: DropDownTextFieldMenu(onAccountTypeChanged: (_) {}),
        ),
      );

      await tapAndSettle(tester, find.byType(DropdownMenu<String>));

      expect(find.text("Teacher"), findsWidgets);
      expect(find.text("Student"), findsWidgets);
    });

    testWidgets("common_dropdown_reports_teacher_as_zero | The mapping is right",
        (WidgetTester tester) async {
      int? chosen;
      await pumpScreen(
        tester,
        Scaffold(
          body: DropDownTextFieldMenu(
            onAccountTypeChanged: (int value) => chosen = value,
          ),
        ),
      );

      await tapAndSettle(tester, find.byType(DropdownMenu<String>));
      await tapAndSettle(tester, find.text("Teacher").last);

      expect(chosen, accountTypeTeacher);
    });

    testWidgets("common_dropdown_reports_student_as_one | The other mapping too",
        (WidgetTester tester) async {
      int? chosen;
      await pumpScreen(
        tester,
        Scaffold(
          body: DropDownTextFieldMenu(
            onAccountTypeChanged: (int value) => chosen = value,
          ),
        ),
      );

      await tapAndSettle(tester, find.byType(DropdownMenu<String>));
      await tapAndSettle(tester, find.text("Student").last);

      expect(chosen, accountTypeStudent);
    });
  });

  group("GB_FloatingActionButton", () {
    testWidgets("common_fab_fires | Tapping the arrow calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(
          floatingActionButton: GB_FloatingActionButton(
            floatingActionButtonIcon: Icons.arrow_forward,
            floatingActionButtonBackgroundColor: kPrimaryColor2,
            floatingActionButtonForegroundColor: kPrimaryColor1,
            onPressed: () => taps++,
          ),
        ),
      );

      await tapAndSettle(tester, find.byIcon(Icons.arrow_forward));

      expect(taps, 1);
    });
  });

  group("GB_SheetTextField", () {
    testWidgets("sheet_field_marks_required | A required field gets an asterisk",
        (WidgetTester tester) async {
      // The asterisk rather than a "(required)" suffix: there is no room for
      // the longer form beside a 140pt half-width field.
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_SheetTextField(
            controller: TextEditingController(),
            label: "Age",
            isRequired: true,
          ),
        ),
      );

      expect(find.text("Age *"), findsOneWidget);
    });

    testWidgets("sheet_field_optional_has_no_asterisk | Optional stays plain",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_SheetTextField(
            controller: TextEditingController(),
            label: "Relation",
          ),
        ),
      );

      expect(find.text("Relation"), findsOneWidget);
      expect(find.text("Relation *"), findsNothing);
    });
  });

  group("GB_GenderSelector", () {
    testWidgets("gender_selector_shows_options | Both choices are drawn",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_GenderSelector(
            options: const ["Male", "Female"],
            selected: null,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text("Male"), findsOneWidget);
      expect(find.text("Female"), findsOneWidget);
    });

    testWidgets("gender_selector_marks_the_choice | The selected box is checked",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_GenderSelector(
            options: const ["Male", "Female"],
            selected: "Female",
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets("gender_selector_fires | Tapping an option calls back",
        (WidgetTester tester) async {
      String? chosen;
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_GenderSelector(
            options: const ["Male", "Female"],
            selected: null,
            onChanged: (String value) => chosen = value,
          ),
        ),
      );

      await tapAndSettle(tester, find.text("Female"));

      expect(chosen, "Female");
    });

    testWidgets("gender_selector_shows_its_error | It fails like the fields around it",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_GenderSelector(
            options: const ["Male", "Female"],
            selected: null,
            onChanged: (_) {},
            errorText: "Select a gender",
          ),
        ),
      );

      expect(find.text("Select a gender"), findsOneWidget);
    });
  });

  group("GB_PillButton", () {
    testWidgets("pill_button_fires | Tapping calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(
            child: GB_PillButton(
              label: "Add to Class",
              onPressed: () => taps++,
            ),
          ),
        ),
      );

      await tapAndSettle(tester, find.text("Add to Class"));

      expect(taps, 1);
    });

    testWidgets("pill_button_null_disables | A null callback disables it",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: Center(
            child: GB_PillButton(label: "Add to Class", onPressed: null),
          ),
        ),
      );

      expect(isButtonDisabled(tester, "Add to Class"), isTrue);
    });
  });

  group("GB_StudentPhotoPicker", () {
    testWidgets("photo_picker_empty_state | It invites a photo",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(body: GB_StudentPhotoPicker(photoPath: null, onTap: () {})),
      );

      expect(find.text("Add photo"), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    });

    testWidgets("photo_picker_fires | Tapping it calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_StudentPhotoPicker(photoPath: null, onTap: () => taps++),
        ),
      );

      await tapAndSettle(tester, find.byIcon(Icons.add_a_photo_outlined));

      expect(taps, 1);
    });
  });
}
