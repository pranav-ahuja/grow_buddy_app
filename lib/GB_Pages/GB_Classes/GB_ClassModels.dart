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
/// filtered, or added to. [GB_ClassPalette] holds the pastels they come from;
/// the teacher picks one when adding the class and can change it from "Edit
/// class" afterwards.
class GB_ClassInfo {
  /// The class id the server assigned, e.g. "CL_000003". Stable, so a rename or
  /// a reorder cannot make two classes collide — names are deliberately not the
  /// key.
  final String id;

  final String name;

  /// "no. of students" on the design — the real count once the backend has one.
  final String subtitle;
  final String imagePath;
  final Color fillColor;
  final Color borderColor;

  /// The `TR_` id of the class teacher — the one teacher answerable for this
  /// class.
  ///
  /// **Null means unassigned**, which is a class the principal has created and
  /// not yet given to anyone, not a class in a broken state.
  final String? teacherId;

  /// The name of the class teacher.
  ///
  /// For the principal's dashboard, which lists every class in the school:
  /// two teachers each having a "Nursery" is normal and allowed, so without
  /// the owner's name that list is two identical tiles. Null when the class is
  /// unassigned, or when the server did not send one.
  final String? teacherName;

  /// Everyone who teaches this class, the class teacher first.
  ///
  /// A class may have several teachers — the principal picks them from the
  /// class screen, several at a time. Empty means nobody teaches it yet.
  final List<GB_ClassTeacher> teachers;

  const GB_ClassInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.imagePath,
    required this.fillColor,
    required this.borderColor,
    this.teacherId,
    this.teacherName,
    this.teachers = const <GB_ClassTeacher>[],
  });

  /// The ids of everyone teaching this class — what the "Add teacher" picker
  /// opens with already highlighted.
  List<String> get teacherIds =>
      teachers.map((GB_ClassTeacher t) => t.teacherId).toList();
}

/// One teacher on a class, as the class screen and its picker read them.
class GB_ClassTeacher {
  const GB_ClassTeacher({
    required this.teacherId,
    required this.fullName,
    this.isClassTeacher = false,
  });

  final String teacherId;
  final String fullName;

  /// True for the class teacher. The picker highlights everyone alike, but the
  /// class screen names the class teacher first and the rest after — a room
  /// with two adults still has one who is answerable for it.
  final bool isClassTeacher;
}

/// One choosable class colour: the tile fill, its border, and the opaque
/// version of the fill that the class screen's header panel uses.
///
/// The three travel together because they are one decision. A teacher picks
/// "Mint", not a fill and a border and a panel, and nothing may pair the fill of
/// one swatch with the border of another.
class GB_ClassColor {
  const GB_ClassColor({
    required this.name,
    required this.fill,
    required this.border,
    required this.panel,
  });

  /// What the swatch is called in the picker's tooltip, and what a confirmation
  /// message can name — "Colour changed to Mint" beats quoting a hex value.
  final String name;

  final Color fill;
  final Color border;

  /// The flattened equivalent of [fill], for the class screen's header panel.
  ///
  /// The tile fills are 50% alpha so they sit softly on the dashboard's white
  /// background; painting the same value across a 352pt panel would wash out
  /// almost to nothing, so the panel uses this instead.
  final Color panel;
}

/// Every colour a class can be — the design's five tints first, then four more
/// in the same register.
///
/// Pastels only, deliberately: the tile fill sits behind the class name and the
/// student count, and a saturated fill would take the contrast out from under
/// both. Anything added here should be mixed to the same recipe as the rest.
///
/// Still a cycle, because a new class is given a colour before the teacher has
/// had a chance to choose one — [GB_ClassStore] uses the next slot along as the
/// default, and the picker starts there.
class GB_ClassPalette {
  const GB_ClassPalette._();

  static const List<GB_ClassColor> all = [
    GB_ClassColor(
      name: "Butter",
      fill: kClassTileYellowFill,
      border: kClassTileYellowBorder,
      panel: Color(0xffFFFCF3),
    ),
    GB_ClassColor(
      name: "Blush",
      fill: kClassTilePinkFill,
      border: kClassTilePinkBorder,
      panel: Color(0xffFFF6F5),
    ),
    GB_ClassColor(
      name: "Sky",
      fill: kClassTileBlueFill,
      border: kClassTileBlueBorder,
      panel: Color(0xffF0FBFF),
    ),
    GB_ClassColor(
      name: "Mint",
      fill: kClassTileGreenFill,
      border: kClassTileGreenBorder,
      panel: Color(0xffEBFFF7),
    ),
    GB_ClassColor(
      name: "Orchid",
      fill: kClassTilePurpleFill,
      border: kClassTilePurpleBorder,
      panel: Color(0xffFFEBFC),
    ),
    GB_ClassColor(
      name: "Peach",
      fill: kClassTilePeachFill,
      border: kClassTilePeachBorder,
      panel: Color(0xffFFF3EA),
    ),
    GB_ClassColor(
      name: "Lavender",
      fill: kClassTileLavenderFill,
      border: kClassTileLavenderBorder,
      panel: Color(0xffF4F0FF),
    ),
    GB_ClassColor(
      name: "Aqua",
      fill: kClassTileAquaFill,
      border: kClassTileAquaBorder,
      panel: Color(0xffE9FAF8),
    ),
    GB_ClassColor(
      name: "Sage",
      fill: kClassTileSageFill,
      border: kClassTileSageBorder,
      panel: Color(0xffF1F7EC),
    ),
  ];

  static int get length => all.length;

  /// The colour in [index], wrapping so a slot past the end is a colour rather
  /// than a crash.
  static GB_ClassColor at(int index) => all[index % all.length];

  static Color fillAt(int index) => at(index).fill;

  static Color borderAt(int index) => at(index).border;

  static Color panelAt(int index) => at(index).panel;

  /// Finds the palette slot a class was given, so the class screen can paint
  /// its header in the same hue the dashboard tile used, and the picker can open
  /// on the colour the class already has.
  static int slotForFill(Color fill) {
    final int index = all.indexWhere(
      (GB_ClassColor color) => color.fill == fill,
    );
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
/// Only [name], [dateOfBirth], [gender], [address], and the class are required
/// — the ones the form insists on. Everything else defaults to empty or null
/// so a teacher can register a student from the minimum and fill the rest in
/// later.
class GB_Student {
  /// The student id the server assigned, e.g. "ST_000007" — the student's
  /// identity, and the id a teacher sees and quotes. Empty only on a student
  /// that has not been sent to the server yet.
  final String studentId;

  final String name;

  /// Stored instead of an age, which would be wrong a year later. [ageYears]
  /// works the age out from it.
  final DateTime dateOfBirth;

  final String gender;
  final String address;

  /// The class the student is in, e.g. "CL_000003". Held as an id, not a
  /// [GB_ClassInfo], so renaming or recolouring a class cannot leave the
  /// student holding a stale copy of it.
  ///
  /// Null only on a student read out of a class file, before the restore has
  /// created the class they are going back into.
  final String? classId;

  /// The student's position in their class by registration order — 1 for the
  /// first registered. Worked out by the server on every read: a new student
  /// gets the next number, and it shifts only when one before them leaves.
  /// Null before the server has seen the student.
  final int? rollNumber;

  /// A photo the teacher picked, as a file path on the device. Null when they
  /// skipped it, in which case [imagePath] is what gets drawn.
  final String? photoPath;

  /// The asset drawn when there is no [photoPath].
  final String imagePath;

  final GB_StudentContact? mother;
  final GB_StudentContact? father;
  final GB_StudentContact? guardian;

  const GB_Student({
    this.studentId = "",
    required this.name,
    required this.dateOfBirth,
    required this.imagePath,
    this.gender = "",
    this.address = "",
    this.classId,
    this.rollNumber,
    this.photoPath,
    this.mother,
    this.father,
    this.guardian,
  });

  /// Completed years of age as of [today] (defaulting to now) — a child is 4
  /// from their fourth birthday until the day before their fifth.
  int ageYears([DateTime? today]) {
    final DateTime now = today ?? DateTime.now();
    final bool hadBirthdayThisYear = now.month > dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day >= dateOfBirth.day);
    return now.year - dateOfBirth.year - (hadBirthdayThisYear ? 0 : 1);
  }
}
