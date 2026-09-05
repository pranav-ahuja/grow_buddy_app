import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// One class in the school — the unit the dashboard lists and the class screen
/// opens.
///
/// This lives in GB_Classes rather than with the home screen because both the
/// dashboard's list and [GB_ClassScreen] are views onto the same thing; the
/// screen that shows classes depends on the class module, not the reverse.
///
/// [fillColor]/[borderColor] travel with the class rather than being picked by
/// list position, so a class keeps its colour when the list is reordered,
/// filtered, or added to. [GB_ClassPalette] hands out the design's five tints.
class GB_ClassInfo {
  /// Stable identity, so a rename or a reorder cannot make two classes collide.
  /// Names are deliberately not used as the key — nothing stops a teacher
  /// creating two classes called "Nursery".
  final int id;

  final String name;

  /// "no. of students" on the design — the real count once the backend has one.
  final String subtitle;
  final String imagePath;
  final Color fillColor;
  final Color borderColor;

  const GB_ClassInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.imagePath,
    required this.fillColor,
    required this.borderColor,
  });
}

/// The five fill/border pairs from the design, in order.
///
/// Kept as a cycle so a sixth class does not crash or come out uncoloured — it
/// simply reuses the first tint. That matters now that teachers can add their
/// own classes and the count is no longer fixed at five.
class GB_ClassPalette {
  const GB_ClassPalette._();

  static const List<Color> _fills = [
    kClassTileYellowFill,
    kClassTilePinkFill,
    kClassTileBlueFill,
    kClassTileGreenFill,
    kClassTilePurpleFill,
  ];

  static const List<Color> _borders = [
    kClassTileYellowBorder,
    kClassTilePinkBorder,
    kClassTileBlueBorder,
    kClassTileGreenBorder,
    kClassTilePurpleBorder,
  ];

  /// The opaque version of each tint, for the class screen's header panel.
  ///
  /// The list tints are 50% alpha so they sit softly on the dashboard's white
  /// background; painting the same value across a 352pt panel would wash out
  /// almost to nothing, so the panel uses these flattened equivalents.
  static const List<Color> _panels = [
    Color(0xffFFFCF3),
    Color(0xffFFF6F5),
    Color(0xffF0FBFF),
    Color(0xffEBFFF7),
    Color(0xffFFEBFC),
  ];

  static int get length => _fills.length;

  static Color fillAt(int index) => _fills[index % _fills.length];

  static Color borderAt(int index) => _borders[index % _borders.length];

  static Color panelAt(int index) => _panels[index % _panels.length];

  /// Finds the palette slot a class was given, so the class screen can paint
  /// its header in the same hue the dashboard tile used.
  static int slotForFill(Color fill) {
    final int index = _fills.indexOf(fill);
    return index == -1 ? 0 : index;
  }
}

/// One tile in the class screen's "Features" row.
///
/// [iconPath] is an asset rather than an [IconData]: the design uses the
/// project's illustrated emoji-style art, which no icon font can reproduce.
class GB_ClassFeature {
  final String label;
  final String iconPath;

  const GB_ClassFeature({required this.label, required this.iconPath});

  /// The six features the design lays out, in its order.
  static const List<GB_ClassFeature> all = [
    GB_ClassFeature(
      label: "Assignment",
      iconPath: "assets/images/features_of_class/assignments.png",
    ),
    GB_ClassFeature(
      label: "Grade Book",
      iconPath: "assets/images/features_of_class/grade_books.png",
    ),
    GB_ClassFeature(
      label: "Resources",
      iconPath: "assets/images/features_of_class/resources.png",
    ),
    GB_ClassFeature(
      label: "Class Schedule",
      iconPath: "assets/images/features_of_class/class_sch.png",
    ),
    // Spelt correctly here even though the design and the asset filename both
    // read "Attendence"; the label is what users read.
    GB_ClassFeature(
      label: "Attendance",
      iconPath: "assets/images/features_of_class/Attendence.png",
    ),
    GB_ClassFeature(
      label: "Fee Payment",
      iconPath: "assets/images/features_of_class/fee_payment.png",
    ),
  ];
}

/// A person to reach about a student — a parent or a guardian.
///
/// One class covers mother, father, and guardian rather than three: they differ
/// only in which fields the form collects (a guardian is asked for an address
/// and a relation, parents are not), and every field is optional on all three,
/// so three near-identical classes would buy nothing.
class GB_StudentContact {
  final String name;
  final String mobile;
  final String email;

  /// Guardians only — parents are not asked for a separate address.
  final String address;

  /// Guardians only, e.g. "Grandmother", "Uncle".
  final String relation;

  const GB_StudentContact({
    this.name = "",
    this.mobile = "",
    this.email = "",
    this.address = "",
    this.relation = "",
  });

  /// True when the teacher filled nothing in for this person.
  ///
  /// Every one of these blocks is optional, so the form uses this to store
  /// `null` instead of a contact made entirely of empty strings — which would
  /// otherwise render as an empty "Mother" row on the student's profile.
  bool get isEmpty =>
      name.isEmpty &&
      mobile.isEmpty &&
      email.isEmpty &&
      address.isEmpty &&
      relation.isEmpty;
}

/// One pupil: what the register-student form collects, and what the class
/// screen's "Students list" row shows.
///
/// Only [name], [age], [gender], and [address] are required — they are the four
/// the form insists on. Everything else defaults to empty or null so a teacher
/// can register a student from the minimum and fill the rest in later.
class GB_Student {
  /// Stable identity, handed out by [GB_StudentStore]. Defaults to -1 for the
  /// placeholder students that are constructed inline rather than registered.
  final int id;

  /// The id a teacher actually sees and quotes, e.g. "GB-0007", assigned at
  /// registration by [GB_StudentStore].
  ///
  /// Kept separate from [id] rather than formatted from it on demand: [id] is
  /// an implementation detail that the backend will eventually own, while this
  /// is a value that goes on registers and report cards and must not change if
  /// the internal key ever does.
  final String studentId;

  final String name;

  /// Free text rather than an int: the design shows "Age" as a caption, and
  /// real data will likely be "4 yrs" or a date of birth rendered as an age.
  final String age;

  final String gender;
  final String address;

  /// The class the student was added to, or null when registered without one.
  /// Held as an id, not a [GB_ClassInfo], so renaming or recolouring a class
  /// cannot leave the student holding a stale copy of it.
  final int? classId;

  /// A photo the teacher picked, as a file path on the device. Null when they
  /// skipped it, in which case [imagePath] is what gets drawn.
  final String? photoPath;

  /// The asset drawn when there is no [photoPath].
  final String imagePath;

  final GB_StudentContact? mother;
  final GB_StudentContact? father;
  final GB_StudentContact? guardian;

  const GB_Student({
    this.id = -1,
    this.studentId = "",
    required this.name,
    required this.age,
    required this.imagePath,
    this.gender = "",
    this.address = "",
    this.classId,
    this.photoPath,
    this.mother,
    this.father,
    this.guardian,
  });
}
