/// The value types behind the class screen: the colour palette, the feature
/// tiles, and the contact block the student form collects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';

void main() {
  group("GB_ClassPalette", () {
    test("palette_has_five_tints | The design's five colours are all there",
        () {
      expect(GB_ClassPalette.length, 5);
    });

    test("palette_wraps | Indexing past the end cycles instead of crashing",
        () {
      expect(GB_ClassPalette.fillAt(5), GB_ClassPalette.fillAt(0));
      expect(GB_ClassPalette.borderAt(6), GB_ClassPalette.borderAt(1));
      expect(GB_ClassPalette.panelAt(12), GB_ClassPalette.panelAt(2));
    });

    test("palette_finds_slot | A tile's fill maps back to its slot", () {
      // This is how the class screen paints its header in the same hue the
      // dashboard tile used.
      expect(GB_ClassPalette.slotForFill(GB_ClassPalette.fillAt(3)), 3);
    });

    test("palette_unknown_fill_is_slot_zero | An unrecognised colour is safe",
        () {
      // A class created before the palette existed, or one whose colour was
      // hand-set, must still render rather than throwing on an index of -1.
      expect(GB_ClassPalette.slotForFill(const Color(0xff123456)), 0);
    });

    test("palette_panels_are_opaque | Header tints are flattened, not alpha",
        () {
      // The list tints are 50% alpha so they sit softly on white; painting one
      // across a 352pt panel would wash out to nothing, so panels are separate
      // opaque equivalents.
      for (int i = 0; i < GB_ClassPalette.length; i++) {
        expect(GB_ClassPalette.panelAt(i).a, 1.0,
            reason: "panel $i should be fully opaque");
      }
    });
  });

  group("GB_ClassFeature", () {
    test("features_are_the_designed_six | All six tiles, in the design's order",
        () {
      expect(
        GB_ClassFeature.all.map((GB_ClassFeature f) => f.label),
        [
          "Assignment",
          "Grade Book",
          "Resources",
          "Class Schedule",
          "Attendance",
          "Fee Payment",
        ],
      );
    });

    test("features_label_is_spelt_correctly | 'Attendance', not the asset name",
        () {
      // The design and the asset filename both read "Attendence". The label is
      // what users read, so it is spelt correctly here on purpose.
      final GB_ClassFeature attendance = GB_ClassFeature.all
          .firstWhere((GB_ClassFeature f) => f.label == "Attendance");

      expect(attendance.iconPath, contains("Attendence.png"));
    });

    test("features_have_icons | Every tile points at an asset", () {
      for (final GB_ClassFeature feature in GB_ClassFeature.all) {
        expect(feature.iconPath, startsWith("assets/images/"));
      }
    });
  });

  group("GB_StudentContact", () {
    test("contact_empty_when_untouched | A blank block reports itself empty",
        () {
      // The form stores null rather than a contact of empty strings, which
      // would otherwise render as an empty "Mother" row on a student profile.
      expect(const GB_StudentContact().isEmpty, isTrue);
    });

    test("contact_not_empty_with_any_field | One filled field is enough", () {
      expect(const GB_StudentContact(name: "Meera").isEmpty, isFalse);
      expect(const GB_StudentContact(mobile: "9990001111").isEmpty, isFalse);
      expect(const GB_StudentContact(relation: "Aunt").isEmpty, isFalse);
    });
  });

  group("GB_Student", () {
    test("student_defaults | Optional fields default rather than being required",
        () {
      const GB_Student student = GB_Student(
        name: "Aarav",
        age: "4",
        imagePath: "assets/images/hs_classes.jpeg",
      );

      expect(student.id, -1);
      expect(student.studentId, "");
      expect(student.gender, "");
      expect(student.classId, isNull);
      expect(student.photoPath, isNull);
      expect(student.mother, isNull);
    });
  });
}
