import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_NotificationStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The notification tab, and — for the principal — the approval queue it
/// carries.
///
/// One screen rather than two, because they are the same thing seen twice: a
/// teacher's request arrives as a notification, and the notification is where
/// it gets answered. Splitting them would mean a principal reading "Asha Rao
/// requests approval for removal of Nursery" and then going somewhere else to
/// find it.
///
/// What each role sees here:
///
/// * the **principal** gets the requests waiting on them at the top, each with
///   Approve and Reject, and their notices below;
/// * a **teacher** gets what became of the things they asked for, and their
///   notices;
/// * a **parent** gets their notices, which is all this screen is for them.
///
/// The split is the server's in every case. `GET /requests` returns the whole
/// school's queue to a principal and only their own rows to a teacher, so this
/// screen never filters and so cannot filter wrongly.
class GB_NotificationsScreen extends StatefulWidget {
  const GB_NotificationsScreen({super.key});

  @override
  State<GB_NotificationsScreen> createState() => _GB_NotificationsScreenState();
}

class _GB_NotificationsScreenState extends State<GB_NotificationsScreen> {
  /// The requests this account may see — the whole queue for a principal,
  /// their own for a teacher.
  List<GB_ChangeRequest> _requests = <GB_ChangeRequest>[];

  bool _isFirstLoad = true;
  String? _loadError;

  /// The request currently being answered, so both its buttons can be
  /// disabled together. A second tap on a slow connection would otherwise send
  /// a second approval — which the server refuses, but with a 409 the reader
  /// has to interpret rather than a button that simply did not act twice.
  int? _deciding;

  bool get _isPrincipal => gIsPrincipal();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final List<GB_ChangeRequest> requests =
          await GB_ApprovalApi.listRequests(token: gRequireToken());
      await GB_NotificationStore.load();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _isFirstLoad = false;
        _loadError = null;
      });
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isFirstLoad = false;
        _loadError = error.message;
      });
    }
  }

  List<GB_ChangeRequest> get _pending =>
      _requests.where((GB_ChangeRequest r) => r.isPending).toList();

  List<GB_ChangeRequest> get _answered =>
      _requests.where((GB_ChangeRequest r) => !r.isPending).toList();

  /// Grants a request, then reloads everything it could have changed.
  ///
  /// The stores are reloaded rather than patched: approving a class creation
  /// adds a class to somebody's dashboard, approving a removal takes a pupil
  /// out and renumbers their classmates, and working out which locally is
  /// re-implementing the server's answer.
  Future<void> _approve(GB_ChangeRequest request) async {
    setState(() => _deciding = request.id);
    try {
      final GB_ActionResult result = await GB_ApprovalApi.approve(
        token: gRequireToken(),
        requestId: request.id,
      );
      await Future.wait([GB_ClassStore.load(), GB_StudentStore.load()]);
      if (!mounted) return;
      gShowSnack(context, result.detail);
      await _refresh();
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      // The likeliest failure is the world having moved on — the class already
      // deleted, the name since taken. The server says which, in a sentence.
      gShowSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  Future<void> _reject(GB_ChangeRequest request) async {
    final String? note = await _askForReason(request);
    // Null is a cancelled dialog: the request stays pending, untouched.
    if (note == null || !mounted) return;

    setState(() => _deciding = request.id);
    try {
      await GB_ApprovalApi.reject(
        token: gRequireToken(),
        requestId: request.id,
        note: note,
      );
      if (!mounted) return;
      gShowSnack(context, "Turned down: ${request.summary}");
      await _refresh();
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      gShowSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  /// Asks why, before turning something down.
  ///
  /// Optional but asked for every time, because "rejected" with no reason is
  /// how a teacher asks again tomorrow in the same words. Returns null if the
  /// dialog was dismissed, and "" if it was submitted empty — which is a
  /// decision to give no reason, not the same thing as backing out.
  Future<String?> _askForReason(GB_ChangeRequest request) {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: kPrimaryColor2,
        title: const Text("Turn this down?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${request.requestedByName} asked for ${request.summary}.",
              style: const TextStyle(
                fontSize: kEventSubtitleTextSize,
                height: 1.4,
                color: kHomeSubtitleTextColor,
              ),
            ),
            const SizedBox(height: 16.0),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: "Reason (optional)",
                hintText: "e.g. We are not opening a KG this year",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kClassTileRadius),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text("Turn down"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: AppBar(
        backgroundColor: kPrimaryColor2,
        surfaceTintColor: kPrimaryColor2,
        elevation: 0.0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: kHomeIconColor),
        titleTextStyle: const TextStyle(
          fontSize: kHomeAppBarTextSize,
          fontWeight: FontWeight.w500,
          color: kHomeTitleTextColor,
        ),
        title: const Text("Notifications"),
        actions: [
          ValueListenableBuilder<GB_NotificationFeed>(
            valueListenable: GB_NotificationStore.feed,
            builder: (context, feed, _) {
              if (feed.unread == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: _markAllRead,
                style: TextButton.styleFrom(foregroundColor: kHomeAccentColor),
                child: const Text("Mark all read"),
              );
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(
            height: 1.0,
            thickness: 1.0,
            color: kHomeAppBarBorderColor,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: kHomeAccentColor,
          child: _buildBody(),
        ),
      ),
    );
  }

  Future<void> _markAllRead() async {
    try {
      await GB_NotificationStore.markAllRead();
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      gShowSnack(context, error.message);
    }
  }

  Widget _buildBody() {
    if (_isFirstLoad) {
      return const Center(
        child: CircularProgressIndicator(color: kHomeAccentColor),
      );
    }

    final String? error = _loadError;
    if (error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(kHomeHorizontalPadding),
        children: [
          const SizedBox(height: 40.0),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: kEventSubtitleTextSize,
              height: 1.4,
              color: kHomeSubtitleTextColor,
            ),
          ),
          const SizedBox(height: 12.0),
          Center(
            child: OutlinedButton(
              onPressed: _refresh,
              style: OutlinedButton.styleFrom(foregroundColor: kHomeAccentColor),
              child: const Text("Try again"),
            ),
          ),
        ],
      );
    }

    return ValueListenableBuilder<GB_NotificationFeed>(
      valueListenable: GB_NotificationStore.feed,
      builder: (context, feed, _) {
        final List<GB_ChangeRequest> pending = _pending;
        final List<GB_ChangeRequest> answered = _answered;

        if (pending.isEmpty &&
            answered.isEmpty &&
            feed.notifications.isEmpty) {
          return _buildEmpty();
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            kHomeHorizontalPadding,
            16.0,
            kHomeHorizontalPadding,
            32.0,
          ),
          children: [
            if (pending.isNotEmpty) ...[
              _sectionHeader(
                _isPrincipal
                    ? "Waiting for you"
                    : "Waiting for the principal",
              ),
              for (final GB_ChangeRequest request in pending)
                _buildRequestCard(request),
              const SizedBox(height: 24.0),
            ],
            if (!_isPrincipal && answered.isNotEmpty) ...[
              // Only on a teacher's screen. The principal's own history is
              // every decision the school has ever made, which is a log, not
              // a notification tab.
              _sectionHeader("What you asked for"),
              for (final GB_ChangeRequest request in answered)
                _buildAnsweredCard(request),
              const SizedBox(height: 24.0),
            ],
            _sectionHeader("Notifications"),
            if (feed.notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  "Nothing yet.",
                  style: TextStyle(
                    fontSize: kEventSubtitleTextSize,
                    color: kHomeSubtitleTextColor,
                  ),
                ),
              )
            else
              for (final GB_Notification notice in feed.notifications)
                _buildNoticeTile(notice),
          ],
        );
      },
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80.0),
        Icon(
          Icons.notifications_none,
          size: 48.0,
          color: kHomeSubtitleTextColor,
        ),
        SizedBox(height: 12.0),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: kHomeHorizontalPadding),
          child: Text(
            "Nothing to read yet.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: kEventSubtitleTextSize,
              height: 1.4,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: kHomeSectionHeaderTextSize,
          fontWeight: FontWeight.w500,
          color: kHomeTitleTextColor,
        ),
      ),
    );
  }

  /// A request the principal can answer, or one the teacher is waiting on.
  Widget _buildRequestCard(GB_ChangeRequest request) {
    final bool busy = _deciding == request.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: kClassTileGreenFill,
        borderRadius: BorderRadius.circular(kClassTileRadius),
        border: Border.all(color: kClassTileGreenBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // On the principal's screen the name leads, because the queue is
            // scanned by who is waiting. On the teacher's it would be their
            // own name, which tells them nothing.
            _isPrincipal
                ? "${request.requestedByName} asked for ${request.summary}"
                : "You asked for ${request.summary}",
            style: const TextStyle(
              fontSize: kEventSubtitleTextSize,
              height: 1.4,
              color: kHomeTitleTextColor,
            ),
          ),
          if (_isPrincipal) ...[
            const SizedBox(height: 12.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => _reject(request),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text("Reject"),
                ),
                const SizedBox(width: 8.0),
                FilledButton(
                  onPressed: busy ? null : () => _approve(request),
                  style: FilledButton.styleFrom(
                    backgroundColor: kHomeAccentColor,
                    foregroundColor: kPrimaryColor2,
                  ),
                  child: Text(busy ? "Working…" : "Approve"),
                ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 6.0),
              child: Text(
                "Waiting for the principal",
                style: TextStyle(
                  fontSize: kFieldLabelTextSize,
                  color: kHomeSubtitleTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One of the teacher's own requests that has been answered.
  Widget _buildAnsweredCard(GB_ChangeRequest request) {
    final bool approved = request.isApproved;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            approved ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: kClassDeleteIconSize,
            color: approved
                ? kHomeAccentColor
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${request.statusLabel} — ${request.summary}",
                  style: const TextStyle(
                    fontSize: kEventSubtitleTextSize,
                    height: 1.4,
                    color: kHomeTitleTextColor,
                  ),
                ),
                // The reason, where one was given. Without it a teacher has
                // only "no", which is not something they can act on.
                if (request.decisionNote.isNotEmpty)
                  Text(
                    request.decisionNote,
                    style: const TextStyle(
                      fontSize: kFieldLabelTextSize,
                      height: 1.4,
                      color: kHomeSubtitleTextColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeTile(GB_Notification notice) {
    return InkWell(
      // A broadcast has no per-reader state to set, so tapping it does
      // nothing rather than failing at the server.
      onTap: notice.isUnread && !notice.isBroadcast
          ? () => _markRead(notice)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The unread dot. Space is reserved either way so the text does
            // not shift left the moment a line is read.
            SizedBox(
              width: 16.0,
              child: notice.isUnread
                  ? const Icon(
                      Icons.circle,
                      size: 8.0,
                      color: kHomeAccentColor,
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.message,
                    style: TextStyle(
                      fontSize: kEventSubtitleTextSize,
                      height: 1.4,
                      fontWeight:
                          notice.isUnread ? FontWeight.w500 : FontWeight.w400,
                      color: kHomeTitleTextColor,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    // Source, day and clock time — the three things the
                    // server stores alongside the message.
                    "${notice.source} · ${_dayLabel(notice.date)} "
                    "at ${notice.clock}"
                    "${notice.isBroadcast ? " · Everyone" : ""}",
                    style: const TextStyle(
                      fontSize: kFieldLabelTextSize,
                      color: kHomeSubtitleTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markRead(GB_Notification notice) async {
    try {
      await GB_NotificationStore.markRead(notice.id);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      gShowSnack(context, error.message);
    }
  }

  /// "Today", "Yesterday", or "20 Sep" — dates read that way in a list that is
  /// mostly recent.
  static String _dayLabel(DateTime date) {
    final DateTime today = DateTime.now();
    final DateTime justToday = DateTime(today.year, today.month, today.day);
    final DateTime justThen = DateTime(date.year, date.month, date.day);
    final int days = justToday.difference(justThen).inDays;

    if (days == 0) return "Today";
    if (days == 1) return "Yesterday";
    return "${date.day} ${_months[date.month - 1]}";
  }

  static const List<String> _months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
}
