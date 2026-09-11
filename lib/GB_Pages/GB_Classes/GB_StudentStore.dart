import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// This device's copy of the teacher's registered students.
///
/// Deliberately the same shape as [GB_ClassStore]: the students live on the
/// server against the signed-in account, and this holds the copy the dashboard
/// and the class screen listen to, so registering a student repaints the class
/// list's counts and the class's student row without either screen keeping a
/// copy that could drift.
class GB_StudentStore {
  const GB_StudentStore._();

  /// Starts empty and is filled by [load].
  static final ValueNotifier<List<GB_Student>> students =
      ValueNotifier<List<GB_Student>>(<GB_Student>[]);

  /// Replaces the local copy with the server's — every student the teacher
  /// has, across all classes, because the dashboard counts them on every tile.
  static Future<void> load() async {
    students.value = await GB_ClassApi.listStudents(token: gRequireToken());
  }

  /// Registers a student on the server and returns them as stored, carrying
  /// the id and roll number the server assigned.
  ///
  /// Reloads afterwards rather than appending the one student: roll numbers
  /// are alphabetical, so a new "Bela" moves every classmate after her down
  /// one, and only the server's list has all of those right.
  ///
  /// Throws [GB_ApiException] if the server refuses — including a 409 when the
  /// same child is already in the class — leaving the local copy untouched.
  static Future<GB_Student> addStudent({
    required String name,
    required DateTime dateOfBirth,
    required String gender,
    required String address,
    required String classId,
    String? photoPath,
    GB_StudentContact? mother,
    GB_StudentContact? father,
    GB_StudentContact? guardian,
  }) async {
    final GB_Student created = await GB_ClassApi.createStudent(
      token: gRequireToken(),
      student: GB_Student(
        name: name.trim(),
        dateOfBirth: dateOfBirth,
        gender: gender,
        address: address.trim(),
        classId: classId,
        photoPath: photoPath,
        imagePath: kClassAvatarImage,
        mother: mother,
        father: father,
        guardian: guardian,
      ),
    );

    try {
      await load();
    } on Exception {
      // The student is registered; only the refresh failed. Show them with the
      // roll number the server gave at creation — the classmates' numbers
      // catch up on the next load.
      students.value = [...students.value, created];
    }
    return created;
  }

  /// The students in one class, in roll-number order.
  static List<GB_Student> inClass(String classId) {
    return students.value
        .where((GB_Student student) => student.classId == classId)
        .toList()
      ..sort(
        (GB_Student a, GB_Student b) =>
            (a.rollNumber ?? 0).compareTo(b.rollNumber ?? 0),
      );
  }

  /// How many students are in one class — what the dashboard tile counts.
  static int countInClass(String classId) {
    return students.value
        .where((GB_Student student) => student.classId == classId)
        .length;
  }

  /// Drops one class's students from the local copy, after the server has
  /// deleted the class.
  ///
  /// Local only on purpose: deleting a class on the server deletes its
  /// students there in the same step. This just brings this device's copy into
  /// line without a second round trip to fetch what is already known.
  static void removeStudentsInClass(String classId) {
    students.value = students.value
        .where((GB_Student student) => student.classId != classId)
        .toList();
  }

  /// Forgets the local copy — on sign-out, so the next account to sign in on
  /// this device does not briefly see the previous teacher's students.
  static void clear() {
    students.value = <GB_Student>[];
  }

  /// Puts the store back to a freshly-launched state, so one test's students
  /// cannot leak into the next.
  @visibleForTesting
  static void resetForTest() => clear();
}
