/// The approval queue and the notification tab, as the app models them.
///
/// Plain data with no behaviour, in their own file so that [GB_ClassApi] can
/// hand back a [GB_ChangeRequest] inside its result without importing the
/// approval service, and the approval service can import the class mapping
/// without the two pointing at each other.
///
/// The wording in both of these is the **server's**, stored when the thing
/// happened. "Asha Rao requests approval for removal of Nursery" has to still
/// say that in a month, after Nursery has been deleted and Asha has left, so
/// nothing here re-renders a sentence from live data.
library;

/// What a teacher asked the principal for, and the answer.
class GB_ChangeRequest {
  const GB_ChangeRequest({
    required this.id,
    required this.kind,
    required this.status,
    required this.requestedByName,
    required this.summary,
    this.classId,
    this.studentId,
    this.decisionNote = "",
    this.createdAt,
  });

  final int id;

  /// "class_create", "class_delete", "student_add" or "student_remove".
  final String kind;

  /// "pending", "approved" or "rejected".
  final String status;

  /// Who asked. The server's stored copy, so it still reads correctly after
  /// the teacher has left.
  final String requestedByName;

  /// The one line to decide from: 'removal of the class "Nursery" and its 12
  /// students'.
  final String summary;

  final String? classId;
  final String? studentId;

  /// Why it was turned down, in the principal's words. Empty when it was not,
  /// or when no reason was given.
  final String decisionNote;

  final DateTime? createdAt;

  bool get isPending => status == "pending";
  bool get isApproved => status == "approved";
  bool get isRejected => status == "rejected";

  /// What the teacher's own list shows against each row.
  String get statusLabel => switch (status) {
        "pending" => "Waiting for the principal",
        "approved" => "Approved",
        "rejected" => "Turned down",
        _ => status,
      };

  static GB_ChangeRequest fromJson(Map<String, dynamic> json) {
    return GB_ChangeRequest(
      id: json["id"] as int,
      kind: (json["kind"] as String?) ?? "",
      status: (json["status"] as String?) ?? "pending",
      requestedByName: (json["requested_by_name"] as String?) ?? "",
      summary: (json["summary"] as String?) ?? "",
      classId: json["class_id"] as String?,
      studentId: json["student_id"] as String?,
      decisionNote: (json["decision_note"] as String?) ?? "",
      createdAt: DateTime.tryParse((json["created_at"] as String?) ?? ""),
    );
  }
}

/// One line in the notification tab.
class GB_Notification {
  const GB_Notification({
    required this.id,
    required this.date,
    required this.time,
    required this.source,
    required this.audience,
    required this.message,
    this.requestId,
    this.readAt,
  });

  final int id;

  /// The day it was raised, and the clock time, stored apart — which is how
  /// the tab reads them: grouped under a day, each line stamped.
  final DateTime date;
  final String time;

  /// Where it came from, in words: a teacher's name, or "GrowBuddy" for
  /// anything the app says in its own voice.
  final String source;

  /// "user" or "broadcast". A school-wide notice reads differently from one
  /// addressed to you, and a broadcast cannot be marked read.
  final String audience;

  final String message;

  /// Set where this line is an approval the reader can decide on the spot.
  /// Null for anything that is only news.
  final int? requestId;

  final DateTime? readAt;

  bool get isUnread => readAt == null;
  bool get isBroadcast => audience == "broadcast";
  bool get isActionable => requestId != null;

  /// "14:32" — the stored time, trimmed of the seconds nobody reads.
  String get clock {
    final List<String> parts = time.split(":");
    return parts.length >= 2 ? "${parts[0]}:${parts[1]}" : time;
  }

  static GB_Notification fromJson(Map<String, dynamic> json) {
    return GB_Notification(
      id: json["id"] as int,
      // A plain calendar date, like a student's birthday — no time, no zone.
      date: DateTime.parse(json["date"] as String),
      time: (json["time"] as String?) ?? "",
      source: (json["source"] as String?) ?? "",
      audience: (json["audience"] as String?) ?? "user",
      message: (json["message"] as String?) ?? "",
      requestId: json["request_id"] as int?,
      readAt: DateTime.tryParse((json["read_at"] as String?) ?? ""),
    );
  }
}

/// The tab's contents and the two numbers its badges need.
///
/// Counted by the server rather than by the app: the unread count has to match
/// what the list shows, and two independent counts of the same thing
/// eventually disagree — usually when the badge says 3 and the list is empty.
class GB_NotificationFeed {
  const GB_NotificationFeed({
    required this.notifications,
    required this.unread,
    required this.pendingRequests,
  });

  final List<GB_Notification> notifications;

  /// The dot on the bell.
  final int unread;

  /// The principal's queue depth, and zero for everyone else — a teacher has
  /// no business knowing how many requests the school is sitting on.
  final int pendingRequests;

  static const GB_NotificationFeed empty = GB_NotificationFeed(
    notifications: <GB_Notification>[],
    unread: 0,
    pendingRequests: 0,
  );

  static GB_NotificationFeed fromJson(Map<String, dynamic> json) {
    final List<dynamic> items =
        (json["notifications"] as List<dynamic>?) ?? <dynamic>[];
    return GB_NotificationFeed(
      notifications: items
          .map((item) => GB_Notification.fromJson(item as Map<String, dynamic>))
          .toList(),
      unread: (json["unread"] as int?) ?? 0,
      pendingRequests: (json["pending_requests"] as int?) ?? 0,
    );
  }
}
