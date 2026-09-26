import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// What came of a create or a delete: it was done, or it is waiting on the
/// principal.
///
/// One shape for all four acts, because **who is asking** decides which of the
/// two happens and no screen should have to reproduce that rule to know what
/// it just did. A principal gets [isDone] with the thing; a teacher gets
/// [isPending] with the request now in the queue.
///
/// [detail] is the server's sentence, shown as-is. It is written there for the
/// same reason every other message in this app is: the app would otherwise
/// have to know who needs approval in order to word its own snackbar, and be
/// wrong the moment that rule changes.
class GB_ActionResult {
  const GB_ActionResult({
    required this.status,
    required this.detail,
    this.classInfo,
    this.student,
    this.request,
  });

  /// "done" or "pending".
  final String status;
  final String detail;

  /// The class that was created, on a principal's create. Null otherwise —
  /// including on a delete, which produces nothing.
  final GB_ClassInfo? classInfo;

  /// The pupil that was registered, on a principal's registration.
  final GB_Student? student;

  /// The request now waiting, on a teacher's.
  final GB_ChangeRequest? request;

  bool get isDone => status == "done";
  bool get isPending => status == "pending";

  static GB_ActionResult fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? classJson =
        json["school_class"] as Map<String, dynamic>?;
    final Map<String, dynamic>? studentJson =
        json["student"] as Map<String, dynamic>?;
    final Map<String, dynamic>? requestJson =
        json["request"] as Map<String, dynamic>?;

    return GB_ActionResult(
      status: (json["status"] as String?) ?? "done",
      detail: (json["detail"] as String?) ?? "",
      classInfo: classJson == null ? null : GB_ClassApi.classFromJson(classJson),
      student:
          studentJson == null ? null : GB_ClassApi.studentFromJson(studentJson),
      request:
          requestJson == null ? null : GB_ChangeRequest.fromJson(requestJson),
    );
  }
}

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

  /// Creates a class, or asks the principal for one.
  ///
  /// Which of the two is the server's decision, not this method's: a
  /// principal's goes straight in, a teacher's becomes a request. The
  /// [GB_ActionResult] says which happened.
  ///
  /// [teacherId] is the class teacher, and only a principal may set it. Null
  /// from a principal creates an **unassigned** class, which is a real thing
  /// in August; from a teacher it is ignored, since the class is filed under
  /// them either way.
  ///
  /// [students] is non-empty only for "Restore class", which sends the class
  /// file's students in the same request so the server can create both in one
  /// transaction — all of it, or none.
  static Future<GB_ActionResult> createClass({
    required String token,
    required String name,
    required int colorSlot,
    String? teacherId,
    List<GB_Student> students = const [],
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      kClassesUrl,
      {
        "name": name,
        "color_slot": colorSlot,
        if (teacherId != null) "teacher_id": teacherId,
        if (students.isNotEmpty) "students": students.map(studentToJson).toList(),
      },
      token: token,
    );
    return GB_ActionResult.fromJson(json);
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

  /// Deletes the class and, server-side, every student in it — or asks the
  /// principal to.
  ///
  /// Reads the reply rather than assuming 204: a teacher's delete raises a
  /// request and leaves the class exactly where it was, and the caller has to
  /// know which of the two it got before it prunes anything locally.
  static Future<GB_ActionResult> deleteClass({
    required String token,
    required String id,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.deleteJson(
      "$kClassesUrl/$id",
      token: token,
    );
    return GB_ActionResult.fromJson(json);
  }

  /// Sets who teaches a class — the principal's "Add teacher" picker.
  ///
  /// The **whole set**, not a difference: the picker knows what it wants the
  /// answer to be, and sending a diff is how an unticked teacher stays
  /// assigned. An empty list unassigns the class, which is a legitimate end
  /// state rather than an error.
  ///
  /// The first id becomes the class teacher, except that a class which already
  /// has one keeps them as long as they are still in the set — so reordering
  /// the list cannot quietly move who is answerable for the room.
  static Future<GB_ClassInfo> setClassTeachers({
    required String token,
    required String id,
    required List<String> teacherIds,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.putJson(
      "$kClassesUrl/$id/teachers",
      {"teacher_ids": teacherIds},
      token: token,
    );
    return classFromJson(json);
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
  static Future<GB_ActionResult> createStudent({
    required String token,
    required GB_Student student,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      kStudentsUrl,
      studentToJson(student),
      token: token,
    );
    return GB_ActionResult.fromJson(json);
  }

  /// Removes a pupil, or asks the principal to.
  ///
  /// The approval step earns itself most obviously here: a pupil removed takes
  /// their attendance history with them, and there is no class file to restore
  /// them from the way there is for a whole class.
  static Future<GB_ActionResult> deleteStudent({
    required String token,
    required String studentId,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.deleteJson(
      "$kStudentsUrl/$studentId",
      token: token,
    );
    return GB_ActionResult.fromJson(json);
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
      // Null when the class is unassigned — one the principal created and has
      // not yet given to anyone.
      teacherId: json["teacher_id"] as String?,
      teacherName: json["teacher_name"] as String?,
      // Everyone teaching it, class teacher first. Absent on the odd response
      // that does not carry them, which reads as an empty list rather than as
      // a class nobody teaches — the two are told apart by teacherId.
      teachers: ((json["teachers"] as List<dynamic>?) ?? <dynamic>[])
          .map((item) => _classTeacherFromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  static GB_ClassTeacher _classTeacherFromJson(Map<String, dynamic> json) {
    return GB_ClassTeacher(
      teacherId: json["teacher_id"] as String,
      fullName: (json["full_name"] as String?) ?? "",
      isClassTeacher: (json["is_class_teacher"] as bool?) ?? false,
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
