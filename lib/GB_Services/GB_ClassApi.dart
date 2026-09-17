import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The backend's classes and students endpoints, and the translation between
/// their JSON and the app's models.
///
/// Every call is scoped to the account behind [token]. That is the whole
/// reason these exist: two devices signed in to one account send two different
/// tokens for the same user, and the server hands both the same classes.
///
/// The JSON shape lives only here. Screens and stores deal in [GB_ClassInfo]
/// and [GB_Student]; if the API's field names change, this is the one file
/// that has to know.
class GB_ClassApi {
  const GB_ClassApi._();

  // --------------------------------------------------------------- classes

  static Future<List<GB_ClassInfo>> listClasses({required String token}) async {
    final List<Map<String, dynamic>> items =
        await GB_ApiClient.getJsonList(kClassesUrl, token: token);
    return items.map(classFromJson).toList();
  }

  /// Creates a class. [students] is non-empty only for "Restore class", which
  /// sends the class file's students in the same request so the server can
  /// create both in one transaction — all of it, or none.
  static Future<GB_ClassInfo> createClass({
    required String token,
    required String name,
    required int colorSlot,
    List<GB_Student> students = const [],
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      kClassesUrl,
      {
        "name": name,
        "color_slot": colorSlot,
        if (students.isNotEmpty) "students": students.map(studentToJson).toList(),
      },
      token: token,
    );
    return classFromJson(json);
  }

  /// Omitted arguments are left out of the request, so the server leaves that
  /// part of the class alone.
  static Future<GB_ClassInfo> updateClass({
    required String token,
    required String id,
    String? name,
    int? colorSlot,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.patchJson(
      "$kClassesUrl/$id",
      {
        if (name != null) "name": name,
        if (colorSlot != null) "color_slot": colorSlot,
      },
      token: token,
    );
    return classFromJson(json);
  }

  /// Deletes the class and, server-side, every student in it.
  static Future<void> deleteClass({
    required String token,
    required String id,
  }) {
    return GB_ApiClient.delete("$kClassesUrl/$id", token: token);
  }

  // -------------------------------------------------------------- students

  static Future<List<GB_Student>> listStudents({required String token}) async {
    final List<Map<String, dynamic>> items =
        await GB_ApiClient.getJsonList(kStudentsUrl, token: token);
    return items.map(studentFromJson).toList();
  }

  /// Registers a student. The server assigns the "ST_000007" id — it is the
  /// only party that can see every device's registrations, so it is the only
  /// one that can hand out the next number without two devices colliding.
  ///
  /// Throws a 409 [GB_ApiException] when the same child is already in the
  /// class: same name, date of birth, address, and parents' details.
  static Future<GB_Student> createStudent({
    required String token,
    required GB_Student student,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      kStudentsUrl,
      studentToJson(student),
      token: token,
    );
    return studentFromJson(json);
  }

  // -------------------------------------------------------------- mapping

  static GB_ClassInfo classFromJson(Map<String, dynamic> json) {
    // The server stores which palette slot, not a colour, so the pastel a slot
    // means stays a UI decision — retuning one reaches every existing class.
    final GB_ClassColor color = GB_ClassPalette.at(json["color_slot"] as int);
    return GB_ClassInfo(
      id: json["class_id"] as String,
      name: json["name"] as String,
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: color.fill,
      borderColor: color.border,
      // Sent by the list endpoint only, so null on a class just created or
      // renamed. The principal's dashboard reloads after either, which is
      // where it matters.
      teacherName: json["teacher_name"] as String?,
    );
  }

  static GB_Student studentFromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] as String?) ?? "";

    // The server keeps the three contact blocks as flat columns; the app keeps
    // them as objects, null when the teacher filled nothing in.
    GB_StudentContact? contact(String prefix) {
      final GB_StudentContact value = GB_StudentContact(
        name: text("${prefix}_name"),
        mobile: text("${prefix}_mobile"),
        email: text("${prefix}_email"),
        address: text("${prefix}_address"),
        relation: text("${prefix}_relation"),
      );
      return value.isEmpty ? null : value;
    }

    return GB_Student(
      studentId: text("student_id"),
      name: text("name"),
      // "2021-04-12". Parsed as a plain calendar date — no time, no zone —
      // so a birthday cannot slide a day either way on a device abroad.
      dateOfBirth: DateTime.parse(json["date_of_birth"] as String),
      gender: text("gender"),
      address: text("address"),
      classId: json["class_id"] as String?,
      rollNumber: json["roll_number"] as int?,
      photoPath: json["photo_path"] as String?,
      imagePath: kClassAvatarImage,
      mother: contact("mother"),
      father: contact("father"),
      guardian: contact("guardian"),
    );
  }

  /// The student as the create endpoints want it.
  ///
  /// [GB_Student.studentId] is sent only when it is set — which is only for a
  /// student read out of a class file, who keeps their original id. A new
  /// registration leaves it empty and the server assigns one.
  static Map<String, dynamic> studentToJson(GB_Student student) {
    final GB_StudentContact mother = student.mother ?? const GB_StudentContact();
    final GB_StudentContact father = student.father ?? const GB_StudentContact();
    final GB_StudentContact guardian =
        student.guardian ?? const GB_StudentContact();

    return {
      if (student.studentId.isNotEmpty) "student_id": student.studentId,
      if (student.classId != null) "class_id": student.classId,
      "name": student.name,
      "date_of_birth": formatDate(student.dateOfBirth),
      "gender": student.gender,
      "address": student.address,
      "photo_path": student.photoPath,
      "mother_name": mother.name,
      "mother_mobile": mother.mobile,
      "mother_email": mother.email,
      "father_name": father.name,
      "father_mobile": father.mobile,
      "father_email": father.email,
      "guardian_name": guardian.name,
      "guardian_relation": guardian.relation,
      "guardian_mobile": guardian.mobile,
      "guardian_address": guardian.address,
    };
  }

  /// A date as the API writes one: "2021-04-12".
  static String formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, "0");
    return "${date.year.toString().padLeft(4, "0")}-${two(date.month)}-"
        "${two(date.day)}";
  }
}
