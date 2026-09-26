import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// One pupil's attendance, totalled.
///
/// The server computes this rather than storing it: a stored total is one more
/// thing to keep in step with the marks, and it would be wrong the first time
/// a teacher corrected a day.
class GB_AttendanceSummary {
  const GB_AttendanceSummary({
    required this.studentId,
    required this.studentName,
    required this.daysRecorded,
    required this.present,
    required this.absent,
    required this.percentPresent,
  });

  final String studentId;
  final String studentName;
  final int daysRecorded;
  final int present;
  final int absent;

  /// Null when no day has been marked yet — **not** zero. "0% attendance" is a
  /// claim about a child; "not recorded yet" is the truth, and the screen says
  /// so instead of printing an alarming number.
  final double? percentPresent;

  bool get hasAnyRecord => daysRecorded > 0;

  factory GB_AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return GB_AttendanceSummary(
      studentId: json["student_id"] as String,
      studentName: json["student_name"] as String? ?? "",
      daysRecorded: json["days_recorded"] as int? ?? 0,
      present: json["present"] as int? ?? 0,
      absent: json["absent"] as int? ?? 0,
      percentPresent: (json["percent_present"] as num?)?.toDouble(),
    );
  }
}

/// One day on a pupil's register.
class GB_AttendanceMark {
  const GB_AttendanceMark({
    required this.date,
    required this.isPresent,
  });

  final DateTime date;

  /// The server stores "P" or "A". Turned into a bool here because the app only
  /// ever asks which of the two it is; a third state would mean revisiting this.
  final bool isPresent;

  factory GB_AttendanceMark.fromJson(Map<String, dynamic> json) {
    return GB_AttendanceMark(
      // A plain calendar date — no time, no zone — so a mark cannot slide a
      // day either way on a device abroad.
      date: DateTime.parse(json["date"] as String),
      isPresent: (json["status"] as String? ?? "A").toUpperCase() == "P",
    );
  }
}

/// What a parent's account can read.
///
/// Every call here is scoped **on the server** by the guardian link: the same
/// `GET /students` that answers a teacher with their class answers a parent
/// with their own children. So this file sends no child id to filter by and
/// cannot get that filter wrong — which is the point, because the thing being
/// filtered is other people's children.
///
/// A parent whose account the school has not linked yet gets empty lists, not
/// an error. They have done nothing wrong and can do nothing about it
/// themselves, so the screen explains rather than failing.
class GB_GuardianApi {
  const GB_GuardianApi._();

  /// This account's children, in roll-number order.
  ///
  /// Reuses `GET /students` rather than adding a parent-only endpoint: the
  /// route is already role-scoped, and a second route returning "the same
  /// thing for parents" is a second place for the scoping to drift.
  static Future<List<Map<String, dynamic>>> listChildren({
    required String token,
  }) {
    return GB_ApiClient.getJsonList(kStudentsUrl, token: token);
  }

  static Future<GB_AttendanceSummary> attendanceSummary({
    required String token,
    required String studentId,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.getJson(
      "$kAttendanceUrl/summary?student_id=$studentId",
      token: token,
    );
    return GB_AttendanceSummary.fromJson(json);
  }

  /// One child's marked days, newest first.
  static Future<List<GB_AttendanceMark>> attendanceHistory({
    required String token,
    required String studentId,
  }) async {
    final List<Map<String, dynamic>> items = await GB_ApiClient.getJsonList(
      "$kAttendanceUrl?student_id=$studentId",
      token: token,
    );
    return items.map(GB_AttendanceMark.fromJson).toList();
  }
}
