import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// One pupil's mark on one day. The server stores "P" or "A".
enum GB_AttendanceStatus {
  present("P"),
  absent("A");

  const GB_AttendanceStatus(this.code);

  final String code;

  static GB_AttendanceStatus fromCode(String? code) =>
      (code ?? "").toUpperCase() == "P" ? present : absent;
}

/// A class's register for one day: student id to mark. Pupils not marked that
/// day are absent from the map, not marked absent.
typedef GB_Register = Map<String, GB_AttendanceStatus>;

/// One pupil's running totals, as `GET /attendance/summary` computes them.
///
/// [percentPresent] is null — not zero — for a pupil with no marks yet. The
/// server draws that distinction deliberately: "0% attendance" is a claim
/// about a child, and "not recorded" is the truth.
class GB_AttendanceSummary {
  const GB_AttendanceSummary({
    required this.daysRecorded,
    required this.present,
    required this.percentPresent,
  });

  final int daysRecorded;
  final int present;
  final double? percentPresent;

  bool get hasMarks => daysRecorded > 0 && percentPresent != null;

  factory GB_AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return GB_AttendanceSummary(
      daysRecorded: (json["days_recorded"] as num?)?.toInt() ?? 0,
      present: (json["present"] as num?)?.toInt() ?? 0,
      percentPresent: (json["percent_present"] as num?)?.toDouble(),
    );
  }
}

/// Taking the register and reading it back — `POST` and `GET /attendance`.
///
/// Marking is a teacher's act; the server refuses the principal, who reads.
class GB_AttendanceApi {
  const GB_AttendanceApi._();

  static Future<GB_Register> classRegister({
    required String token,
    required String classId,
    required DateTime date,
  }) async {
    final List<Map<String, dynamic>> items = await GB_ApiClient.getJsonList(
      "$kAttendanceUrl?class_id=$classId"
      "&date=${GB_ClassApi.formatDate(date)}",
      token: token,
    );
    return _registerFrom(items);
  }

  /// Saves one class's register for one day in a single request. Re-posting
  /// a day updates it, which is how a correction is made. Returns the day as
  /// the server now holds it.
  static Future<GB_Register> submitRegister({
    required String token,
    required String classId,
    required DateTime date,
    required GB_Register marks,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      kAttendanceUrl,
      {
        "class_id": classId,
        "date": GB_ClassApi.formatDate(date),
        "entries": [
          for (final MapEntry<String, GB_AttendanceStatus> mark
              in marks.entries)
            {"student_id": mark.key, "status": mark.value.code},
        ],
      },
      token: token,
    );
    // The route answers with a list, which the client wraps as {"data": ...}.
    final List<dynamic> items = (json["data"] as List<dynamic>?) ?? const [];
    return _registerFrom(items.cast<Map<String, dynamic>>());
  }

  /// One pupil's totals for the profile screen's attendance card.
  ///
  /// Computed by the server on every read rather than stored, so a day a
  /// teacher corrects is reflected here without anything else being updated.
  /// The route reads for a guardian as well as for staff, so a parent opening
  /// their own child's profile gets the same card.
  static Future<GB_AttendanceSummary> studentSummary({
    required String token,
    required String studentId,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.getJson(
      "$kAttendanceUrl/summary?student_id=$studentId",
      token: token,
    );
    return GB_AttendanceSummary.fromJson(json);
  }

  static GB_Register _registerFrom(List<Map<String, dynamic>> items) {
    return {
      for (final Map<String, dynamic> item in items)
        item["student_id"] as String:
            GB_AttendanceStatus.fromCode(item["status"] as String?),
    };
  }
}
