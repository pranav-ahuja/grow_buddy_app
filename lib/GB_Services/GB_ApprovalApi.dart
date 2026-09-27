import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The approval queue and the notification tab.
///
/// Two sets of endpoints that only make sense together: a teacher's request is
/// raised by the ordinary class and student calls in [GB_ClassApi], it arrives
/// here as something the principal can read and answer, and both the arrival
/// and the answer turn up in somebody's notifications.
///
/// **Scope is the server's, as everywhere else in this app.** The same
/// `GET /requests` returns the whole school's queue to a principal and only
/// their own rows to a teacher; the same `GET /notifications` returns each
/// account its own. Nothing here filters, so nothing here can filter wrongly.
class GB_ApprovalApi {
  const GB_ApprovalApi._();

  // -------------------------------------------------------------- requests

  /// The requests this account may see, newest first.
  ///
  /// [status] narrows it — "pending" is what the principal's queue opens on.
  /// Left out, the whole history comes back, which is what a teacher's "My
  /// requests" list wants: theirs is mostly interesting for what was decided.
  static Future<List<GB_ChangeRequest>> listRequests({
    required String token,
    String? status,
  }) async {
    final String url =
        status == null ? kRequestsUrl : "$kRequestsUrl?status=$status";
    final List<Map<String, dynamic>> items =
        await GB_ApiClient.getJsonList(url, token: token);
    return items.map(GB_ChangeRequest.fromJson).toList();
  }

  /// Grants a request and carries out what it asked for.
  ///
  /// Comes back with whatever the change produced — the new class, or the new
  /// pupil — so the screen can say what it just brought into being without a
  /// second round trip.
  static Future<GB_ActionResult> approve({
    required String token,
    required int requestId,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      "$kRequestsUrl/$requestId/approve",
      const <String, dynamic>{},
      token: token,
    );
    return GB_ActionResult.fromJson(json);
  }

  /// Turns a request down, with the reason where one was given.
  ///
  /// The note is worth collecting: "rejected" on its own is how a teacher asks
  /// again tomorrow in the same words.
  static Future<GB_ChangeRequest> reject({
    required String token,
    required int requestId,
    String note = "",
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      "$kRequestsUrl/$requestId/reject",
      {"note": note},
      token: token,
    );
    return GB_ChangeRequest.fromJson(json);
  }

  // --------------------------------------------------------- notifications

  static Future<GB_NotificationFeed> listNotifications({
    required String token,
  }) async {
    final Map<String, dynamic> json =
        await GB_ApiClient.getJson(kNotificationsUrl, token: token);
    return GB_NotificationFeed.fromJson(json);
  }

  /// Marks one line read.
  ///
  /// Only an individual notice — a broadcast's read state is a column on the
  /// row everybody shares, so the server refuses it rather than clearing it
  /// for the whole school.
  static Future<GB_Notification> markRead({
    required String token,
    required int notificationId,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      "$kNotificationsUrl/$notificationId/read",
      const <String, dynamic>{},
      token: token,
    );
    return GB_Notification.fromJson(json);
  }

  /// Clears this account's unread notices in one go, so the bell's badge can
  /// actually be got rid of. Returns the tab as it now stands.
  static Future<GB_NotificationFeed> markAllRead({
    required String token,
  }) async {
    final Map<String, dynamic> json = await GB_ApiClient.postJson(
      "$kNotificationsUrl/read",
      const <String, dynamic>{},
      token: token,
    );
    return GB_NotificationFeed.fromJson(json);
  }
}
