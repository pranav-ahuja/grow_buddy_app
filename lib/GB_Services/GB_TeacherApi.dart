import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// A teacher as the principal's pickers need them: an id, a name, and enough
/// beside it to tell two people apart.
///
/// Deliberately thin. The server's `GET /teachers` returns whole records —
/// date of birth, address, emergency contacts — and none of that belongs in a
/// list of names to tap. What is kept is what the "Add teacher" sheet shows.
class GB_TeacherSummary {
  const GB_TeacherSummary({
    required this.teacherId,
    required this.fullName,
    this.email,
    this.phone,
    this.classNames = const <String>[],
  });

  final String teacherId;
  final String fullName;

  final String? email;
  final String? phone;

  /// The classes they already take. Shown under the name because two teachers
  /// can share one, and "Asha Rao" twice with nothing to tell them apart is
  /// the moment a principal assigns the wrong one.
  final List<String> classNames;

  /// The line under the name in the picker: what they already teach, or a
  /// contact when they teach nothing yet.
  String get subtitle {
    if (classNames.isNotEmpty) return classNames.join(" · ");
    final String? contact = email ?? phone;
    return contact ?? "No classes yet";
  }

  static GB_TeacherSummary fromJson(Map<String, dynamic> json) {
    final List<dynamic> classes =
        (json["classes"] as List<dynamic>?) ?? <dynamic>[];
    return GB_TeacherSummary(
      teacherId: json["teacher_id"] as String,
      fullName: (json["full_name"] as String?) ?? "",
      email: json["email"] as String?,
      phone: json["phone"] as String?,
      classNames: classes
          .map((item) => ((item as Map<String, dynamic>)["name"] as String?) ?? "")
          .where((String name) => name.isNotEmpty)
          .toList(),
    );
  }
}

/// The teachers endpoint, as far as the app uses it.
class GB_TeacherApi {
  const GB_TeacherApi._();

  /// Every teacher in the school.
  ///
  /// **The principal's list alone** — the server refuses a teacher with 403,
  /// on the reasoning that a teacher has no business enumerating their
  /// colleagues. So only call it from a screen the principal is on; a teacher
  /// reaching it is a bug in the calling screen, not a permission to widen.
  static Future<List<GB_TeacherSummary>> listTeachers({
    required String token,
  }) async {
    final List<Map<String, dynamic>> items =
        await GB_ApiClient.getJsonList(kTeachersUrl, token: token);
    return items.map(GB_TeacherSummary.fromJson).toList();
  }
}
