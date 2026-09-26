import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeAppBar.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_GuardianApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The parent's home screen.
///
/// The role is called "student", but the app is on a parent's phone, so this
/// screen is written for whoever is holding it: their child's class, and how
/// that child's attendance is going.
///
/// **A parent may have more than one child at the school**, which is why the
/// top of the screen is a picker rather than a single name. The link table is
/// many-to-many for that reason, and a dashboard that assumed one child would
/// silently hide the second.
///
/// Everything here is **read-only**. Editing a child's details and asking for
/// a class to be removed both have to notify the teacher and the principal,
/// and notifications are not built yet — shipping the edit without the notice
/// would be shipping half of a safety mechanism.
///
/// Four of the things this screen is eventually meant to show — the grade
/// sheet, the teacher's messages, event details and the diary — have no data
/// behind them anywhere in the project yet. They are listed at the bottom as
/// plainly not-yet rather than faked with placeholder rows, because a
/// convincing-looking empty grade sheet is worse than an honest gap.
class GB_StudentDashboard extends StatefulWidget {
  const GB_StudentDashboard({super.key});

  @override
  State<GB_StudentDashboard> createState() => _GB_StudentDashboardState();
}

class _GB_StudentDashboardState extends State<GB_StudentDashboard>
    with WidgetsBindingObserver {
  /// The children this account is linked to. Empty until the school links it.
  List<GB_Student> _children = <GB_Student>[];

  /// Which child the screen is showing. Null until the first load lands.
  String? _selectedStudentId;

  final Map<String, GB_AttendanceSummary> _summaries =
      <String, GB_AttendanceSummary>{};

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Reloads on return to the foreground — the same reasoning as the staff
  /// dashboard. A parent opening the app is about to look at today's mark, and
  /// today's mark may have been taken since they last looked.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      // The classes come along because the child's class tile is drawn from
      // them, and `GET /classes` for a parent is already scoped to the classes
      // their children are in.
      await Future.wait([GB_ClassStore.load(), GB_StudentStore.load()]);

      final List<GB_Student> children = GB_StudentStore.students.value;

      // Keep the current child selected across a refresh where possible;
      // repainting back to the first one would be jarring for a parent who had
      // deliberately switched to their second.
      String? selected = _selectedStudentId;
      if (selected == null ||
          !children.any((GB_Student s) => s.studentId == selected)) {
        selected = children.isEmpty ? null : children.first.studentId;
      }

      final Map<String, GB_AttendanceSummary> summaries = {};
      if (selected != null) {
        summaries[selected] = await GB_GuardianApi.attendanceSummary(
          token: gRequireToken(),
          studentId: selected,
        );
      }

      if (!mounted) return;
      setState(() {
        _children = children;
        _selectedStudentId = selected;
        _summaries
          ..clear()
          ..addAll(summaries);
        _isLoading = false;
        _loadError = null;
      });
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.message;
      });
    }
  }

  Future<void> _selectChild(String studentId) async {
    setState(() => _selectedStudentId = studentId);

    if (_summaries.containsKey(studentId)) return;

    try {
      final GB_AttendanceSummary summary =
          await GB_GuardianApi.attendanceSummary(
        token: gRequireToken(),
        studentId: studentId,
      );
      if (!mounted) return;
      setState(() => _summaries[studentId] = summary);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      gShowSnack(context, error.message);
    }
  }

  GB_Student? get _selectedChild {
    final String? id = _selectedStudentId;
    if (id == null) return null;
    for (final GB_Student child in _children) {
      if (child.studentId == id) return child;
    }
    return null;
  }

  /// The class the selected child is in, from the store the server scoped.
  GB_ClassInfo? get _selectedClass {
    final String? classId = _selectedChild?.classId;
    if (classId == null) return null;
    return GB_ClassStore.byId(classId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: const GB_HomeAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: kHomeAccentColor,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              kHomeHorizontalPadding,
              16.0,
              kHomeHorizontalPadding,
              32.0,
            ),
            children: [_buildBody()],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48.0),
        child: Center(
          child: CircularProgressIndicator(color: kHomeAccentColor),
        ),
      );
    }

    final String? error = _loadError;
    if (error != null) return _buildError(error);

    if (_children.isEmpty) return _buildNotLinkedYet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGreeting(),
        const SizedBox(height: 20.0),
        // Only when there is a choice to make. One child and a picker would be
        // a control that does nothing.
        if (_children.length > 1) ...[
          _buildChildPicker(),
          const SizedBox(height: 20.0),
        ],
        _buildClassCard(),
        const SizedBox(height: 20.0),
        _buildAttendanceCard(),
        const SizedBox(height: 28.0),
        _buildComingSoon(),
      ],
    );
  }

  Widget _buildGreeting() {
    final String name = gCurrentUser?.fullName ?? "there";
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hi ${name.split(" ").first}!",
            style: const TextStyle(
              fontSize: kHomeSectionHeaderTextSize,
              fontWeight: FontWeight.w500,
              color: kHomeTitleTextColor,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            _children.length == 1
                ? "Here's how ${_selectedChild?.name ?? "your child"} is doing."
                : "You have ${_children.length} children at the school.",
            style: const TextStyle(
              fontSize: kEventSubtitleTextSize,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Shown only for a parent with more than one child at the school.
  Widget _buildChildPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final GB_Student child in _children)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(child.name),
                selected: child.studentId == _selectedStudentId,
                onSelected: (_) => _selectChild(child.studentId),
                selectedColor: kClassTileGreenFill,
                side: const BorderSide(color: kClassTileGreenBorder),
                labelStyle: const TextStyle(
                  fontSize: kPillButtonTextSize,
                  color: kHomeTitleTextColor,
                ),
                backgroundColor: kPrimaryColor2,
              ),
            ),
        ],
      ),
    );
  }

  /// The child's class, in the colour the teacher chose.
  ///
  /// Not tappable and carrying no menu: a parent cannot rename it, recolour it
  /// or delete it — the requirement is explicit that the colour stays as the
  /// teacher set it, and the server refuses all three regardless.
  Widget _buildClassCard() {
    final GB_ClassInfo? classInfo = _selectedClass;

    if (classInfo == null) {
      return _buildPanel(
        icon: Icons.meeting_room_outlined,
        title: "Class",
        body: "Not in a class yet.",
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: classInfo.fillColor,
        border: Border.all(color: classInfo.borderColor),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      padding: const EdgeInsets.all(kClassTilePadding),
      child: Row(
        children: [
          CircleAvatar(
            radius: kClassTileAvatarRadius,
            backgroundImage: AssetImage(classInfo.imagePath),
          ),
          const SizedBox(width: kClassTileGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classInfo.name,
                  style: const TextStyle(
                    fontSize: kHomeCardTitleTextSize,
                    fontWeight: FontWeight.w500,
                    color: kHomeTitleTextColor,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  [
                    if (classInfo.teacherName != null &&
                        classInfo.teacherName!.isNotEmpty)
                      "Teacher: ${classInfo.teacherName}",
                    if (_selectedChild?.rollNumber != null)
                      "Roll no. ${_selectedChild!.rollNumber}",
                  ].join(" · "),
                  style: const TextStyle(
                    fontSize: kClassSubtitleTextSize,
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

  Widget _buildAttendanceCard() {
    final String? id = _selectedStudentId;
    final GB_AttendanceSummary? summary = id == null ? null : _summaries[id];

    if (summary == null) {
      return _buildPanel(
        icon: Icons.fact_check_outlined,
        title: "Attendance",
        body: "Loading…",
      );
    }

    // "Not recorded yet" rather than 0%. Zero per cent is a claim about a
    // child, and the truth is that nobody has marked a day.
    if (!summary.hasAnyRecord) {
      return _buildPanel(
        icon: Icons.fact_check_outlined,
        title: "Attendance",
        body: "No days marked yet.",
      );
    }

    final double percent = summary.percentPresent ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        border: Border.all(color: kHomeCardBorderColor),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      padding: const EdgeInsets.all(kClassTilePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 20.0,
                color: kHomeIconColor,
              ),
              const SizedBox(width: 10.0),
              const Text(
                "Attendance",
                style: TextStyle(
                  fontSize: kClassSectionHeaderSize,
                  fontWeight: FontWeight.w500,
                  color: kHomeTitleTextColor,
                ),
              ),
              const Spacer(),
              Text(
                "${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1)}%",
                style: const TextStyle(
                  fontSize: kHomeCardTitleTextSize,
                  fontWeight: FontWeight.w500,
                  color: kHomeAccentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 8.0,
              backgroundColor: kClassRowWashColor,
              color: kHomeAccentColor,
            ),
          ),
          const SizedBox(height: 12.0),
          Text(
            "Present ${summary.present} of ${summary.daysRecorded} "
            "${summary.daysRecorded == 1 ? "day" : "days"}"
            "${summary.absent == 0 ? "" : " · absent ${summary.absent}"}",
            style: const TextStyle(
              fontSize: kClassSubtitleTextSize,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ],
      ),
    );
  }

  /// The parts of this screen that have no data behind them yet.
  ///
  /// Named rather than hidden: a parent who was told the app shows a grade
  /// sheet should be able to see that it is coming, and a screen that quietly
  /// omits four of its six promised sections reads as broken.
  Widget _buildComingSoon() {
    const List<(IconData, String)> pending = [
      (Icons.grading_outlined, "Grade sheet"),
      (Icons.forum_outlined, "Messages from the teacher"),
      (Icons.event_outlined, "Events"),
      (Icons.menu_book_outlined, "Diary notes"),
      (Icons.notifications_none, "Notifications"),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Coming soon",
          style: TextStyle(
            fontSize: kClassSectionHeaderSize,
            fontWeight: FontWeight.w500,
            color: kHomeTitleTextColor,
          ),
        ),
        const SizedBox(height: 8.0),
        for (final (IconData icon, String label) in pending)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                Icon(icon, size: 18.0, color: kHomeSubtitleTextColor),
                const SizedBox(width: 12.0),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: kEventSubtitleTextSize,
                    color: kHomeSubtitleTextColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// What a parent sees before the school has linked their account.
  ///
  /// The link can only be made by staff — a parent cannot claim a child — so
  /// this explains rather than offering an action they do not have. Telling
  /// them who to ask is the only useful thing the screen can do.
  Widget _buildNotLinkedYet() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40.0),
      child: Column(
        children: [
          const Icon(
            Icons.family_restroom_outlined,
            size: 64.0,
            color: kHomeIconColor,
          ),
          const SizedBox(height: 16.0),
          GB_H1HeadingText(
            inputText: "Hi ${(gCurrentUser?.fullName ?? "there").split(" ").first}!",
            inputTextAlign: TextAlign.center,
          ),
          const SizedBox(height: 8.0),
          const GB_H2HeadingText(
            inputText:
                "Your account isn't linked to a child yet. Ask your child's "
                "teacher or the principal to connect it, then pull down to "
                "refresh.",
            inputTextAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40.0),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: kEventSubtitleTextSize,
              height: 1.4,
              color: kHomeSubtitleTextColor,
            ),
          ),
          const SizedBox(height: 12.0),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _loadError = null;
              });
              _refresh();
            },
            style: OutlinedButton.styleFrom(foregroundColor: kHomeAccentColor),
            child: const Text("Try again"),
          ),
        ],
      ),
    );
  }

  /// A plain bordered card, for the states that are one line of text.
  Widget _buildPanel({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        border: Border.all(color: kHomeCardBorderColor),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      padding: const EdgeInsets.all(kClassTilePadding),
      child: Row(
        children: [
          Icon(icon, size: 20.0, color: kHomeIconColor),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: kClassSectionHeaderSize,
                    fontWeight: FontWeight.w500,
                    color: kHomeTitleTextColor,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: kClassSubtitleTextSize,
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
}
