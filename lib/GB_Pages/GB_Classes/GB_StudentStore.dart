import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassArchive.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The registered students, and the only place they are mutated.
///
/// Deliberately the same shape as [GB_ClassStore]: a [ValueNotifier] the
/// dashboard and the class screen listen to, so registering a student repaints
/// the class list's counts and the class's student row without either screen
/// keeping a copy that could drift.
///
/// Everything here is in memory, so registrations are lost when the app is
/// killed. That is deliberate for now — there is no students endpoint on the
/// backend yet. When there is, [addStudent] becomes the POST and a `load`
/// becomes the GET; no caller changes, because they already read [students].
class GB_StudentStore {
  const GB_StudentStore._();

  static int _nextId = 0;

  /// The serial behind [formatStudentId]. Separate from [_nextId] and starting
  /// at 1 because it is a number teachers read: ids run from GB-0001, and a
  /// removed student does not free their id for the next one.
  static int _nextStudentNumber = 1;

  /// Renders a serial as the id a teacher sees, e.g. 7 -> "GB-0007".
  static String formatStudentId(int number) {
    return "$kStudentIdPrefix${number.toString().padLeft(kStudentIdDigits, "0")}";
  }

  /// Starts empty rather than seeded: unlike classes, an empty student list is
  /// the truth for a new teacher, and the class screen has its own empty state.
  static final ValueNotifier<List<GB_Student>> students =
      ValueNotifier<List<GB_Student>>(<GB_Student>[]);

  /// Registers a student and returns them.
  ///
  /// A new list is assigned rather than the existing one mutated, for the same
  /// reason as in [GB_ClassStore]: ValueNotifier compares with `==`, so an
  /// in-place mutation would tell no listener anything had changed.
  static GB_Student addStudent({
    required String name,
    required String age,
    required String gender,
    required String address,
    int? classId,
    String? photoPath,
    GB_StudentContact? mother,
    GB_StudentContact? father,
    GB_StudentContact? guardian,
  }) {
    final GB_Student created = GB_Student(
      id: _nextId++,
      studentId: formatStudentId(_nextStudentNumber++),
      name: name.trim(),
      age: age.trim(),
      gender: gender,
      address: address.trim(),
      classId: classId,
      photoPath: photoPath,
      imagePath: kClassAvatarImage,
      mother: mother,
      father: father,
      guardian: guardian,
    );

    students.value = [...students.value, created];
    return created;
  }

  /// The students in one class, in registration order.
  static List<GB_Student> inClass(int classId) {
    return students.value
        .where((GB_Student student) => student.classId == classId)
        .toList();
  }

  /// How many students are in one class — what the dashboard tile counts.
  static int countInClass(int classId) {
    return students.value
        .where((GB_Student student) => student.classId == classId)
        .length;
  }

  /// Puts the store back to a freshly-launched state.
  ///
  /// Resets both counters, not just the list: [_nextStudentNumber] is what
  /// renders as "GB-0001", so leaving it alone would make a test's expected
  /// student id depend on how many students earlier tests had registered.
  @visibleForTesting
  static void resetForTest() {
    _nextId = 0;
    _nextStudentNumber = 1;
    students.value = <GB_Student>[];
  }

  static void removeStudent(int id) {
    students.value = students.value
        .where((GB_Student student) => student.id != id)
        .toList();
  }

  /// Drops every student in one class — what deleting a class has to do to
  /// them.
  ///
  /// Without this the students would survive their class as records nothing
  /// lists, and would silently reappear if a later class were handed the same
  /// id. The archive written before the delete is what makes this recoverable.
  static void removeStudentsInClass(int classId) {
    students.value = students.value
        .where((GB_Student student) => student.classId != classId)
        .toList();
  }

  /// Puts archived students back, into the class [classId].
  ///
  /// Their original student ids are kept — that is the point of a restore; a
  /// pupil whose id changed would no longer match the paper registers and
  /// records written against it. Fresh internal ids are handed out because the
  /// old ones belonged to a list this one no longer is.
  ///
  /// [_nextStudentNumber] is pushed past every restored serial afterwards, so
  /// the next registration cannot reissue an id that just came back.
  static List<GB_Student> restoreStudents(
    List<GB_Student> archived, {
    required int classId,
  }) {
    final List<GB_Student> restored = archived
        .map(
          (GB_Student student) => GB_Student(
            id: _nextId++,
            studentId: student.studentId,
            name: student.name,
            age: student.age,
            gender: student.gender,
            address: student.address,
            classId: classId,
            photoPath: student.photoPath,
            imagePath: student.imagePath,
            mother: student.mother,
            father: student.father,
            guardian: student.guardian,
          ),
        )
        .toList();

    students.value = [...students.value, ...restored];

    for (final GB_Student student in restored) {
      final int? serial = GB_ClassArchive.serialInStudentId(student.studentId);
      if (serial != null && serial >= _nextStudentNumber) {
        _nextStudentNumber = serial + 1;
      }
    }

    return restored;
  }
}
