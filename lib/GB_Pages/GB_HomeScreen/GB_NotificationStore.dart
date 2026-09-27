import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// This device's copy of the notification tab.
///
/// The same shape as [GB_ClassStore] and [GB_StudentStore], and for the same
/// reason: the bell sits in the app bar and the list sits on its own screen,
/// and both have to show the same unread count without either keeping a
/// tally that could drift from the other's.
///
/// The counts are the **server's**, carried on every load. The bell could
/// count unread rows itself, and it would be right until the day the list is
/// paginated — at which point the badge would quietly start reporting "unread
/// among the fifty I happen to be holding". Reading the number the server
/// sends costs nothing and cannot develop that bug.
///
/// There is no push. The feed reloads when the dashboard opens, when the app
/// returns to the foreground, on pull-to-refresh, and after the principal
/// answers a request — which is every moment somebody is about to look at it.
class GB_NotificationStore {
  const GB_NotificationStore._();

  static final ValueNotifier<GB_NotificationFeed> feed =
      ValueNotifier<GB_NotificationFeed>(GB_NotificationFeed.empty);

  /// Replaces the local copy with the server's.
  ///
  /// Throws [GB_ApiException] like every other load; callers on the dashboard
  /// swallow it, because a bell that could not refresh is not worth
  /// interrupting someone over.
  static Future<void> load() async {
    feed.value = await GB_ApprovalApi.listNotifications(token: gRequireToken());
  }

  /// Loads without throwing — for the places where the notifications are a
  /// side errand rather than the thing being looked at.
  ///
  /// The dashboard fetches classes, students and this together; a failure here
  /// must not be what stops a teacher seeing their classes.
  static Future<void> loadQuietly() async {
    try {
      await load();
    } on Exception {
      // Keeps whatever was last loaded. The badge going stale for a minute is
      // a smaller problem than an error over something nobody asked for.
    }
  }

  static Future<void> markRead(int notificationId) async {
    await GB_ApprovalApi.markRead(
      token: gRequireToken(),
      notificationId: notificationId,
    );
    await load();
  }

  static Future<void> markAllRead() async {
    feed.value = await GB_ApprovalApi.markAllRead(token: gRequireToken());
  }

  /// The number on the bell.
  static int get unread => feed.value.unread;

  /// How many requests are waiting on the principal, and **zero for everybody
  /// else** — the server decides that, not this getter.
  static int get pendingRequests => feed.value.pendingRequests;

  /// Forgets the local copy — on sign-out, so the next account to sign in on
  /// this device does not briefly see the previous user's notices.
  static void clear() {
    feed.value = GB_NotificationFeed.empty;
  }

  @visibleForTesting
  static void resetForTest() => clear();
}
