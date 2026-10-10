import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AttendanceApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// Which half of the profile is on screen.
enum _GB_ProfileTab { personal, academics }

/// One pupil's profile, opened from the class screen's student list.
///
/// Layout follows the Figma frame `2047-7898` (`claude_ui/ui_student_1.png`):
/// the pupil's photo, an attendance card, then a Personal / Academics pill
/// pair above a flat list of fields — rules between rows rather than a box
/// around them, which is what separates this list from the account profile's
/// bordered details card.
///
/// **The Personal half only.** Academics draws an empty state: the tables
/// behind it are still being designed, and a section wired to nothing would
/// only have to be rewritten once they exist.
///
/// The fields are a deliberate subset of what `students` stores, and a
/// deliberate departure from the frame — see [_buildPersonalFields].
class GB_StudentProfileScreen extends StatefulWidget {
  const GB_StudentProfileScreen({
    super.key,
    required this.student,
    this.onMenu,
  });

  /// The pupil as the list had them, and the fallback when the store no longer
  /// does. A pupil removed while their profile is open keeps drawing the
  /// details that were already on screen rather than blanking out underneath
  /// the teacher.
  final GB_Student student;

  /// The frame's overflow button. Null draws nothing and leaves the title
  /// where it sits, which is how a parent's account sees the screen — the
  /// menu behind it edits and deletes, and only staff may.
  final void Function(GB_Student)? onMenu;

  static Future<void> open(
    BuildContext context,
    GB_Student student, {
    void Function(GB_Student)? onMenu,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (BuildContext context) =>
            GB_StudentProfileScreen(student: student, onMenu: onMenu),
      ),
    );
  }

  @override
  State<GB_StudentProfileScreen> createState() =>
      _GB_StudentProfileScreenState();
}

class _GB_StudentProfileScreenState extends State<GB_StudentProfileScreen> {
  _GB_ProfileTab _tab = _GB_ProfileTab.personal;

  GB_AttendanceSummary? _summary;
  bool _isLoadingSummary = true;

  /// Kept to be shown in the card's own place rather than as a snack: the rest
  /// of the profile is readable without the totals, so a failure here should
  /// not interrupt the screen.
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  /// The totals are the one thing on this screen that is not already in the
  /// store, so this is the only request the profile makes.
  Future<void> _loadSummary() async {
    setState(() {
      _isLoadingSummary = true;
      _summaryError = null;
    });
    try {
      final GB_AttendanceSummary summary =
          await GB_AttendanceApi.studentSummary(
        token: gRequireToken(),
        studentId: widget.student.studentId,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoadingSummary = false;
      });
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingSummary = false;
        _summaryError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      body: SafeArea(
        // Listening to the store rather than holding a copy: a pupil edited
        // from the menu above is redrawn here without reopening the screen.
        child: ValueListenableBuilder<List<GB_Student>>(
          valueListenable: GB_StudentStore.students,
          builder: (
            BuildContext context,
            List<GB_Student> students,
            Widget? child,
          ) {
            final GB_Student current = students.firstWhere(
              (GB_Student s) => s.studentId == widget.student.studentId,
              orElse: () => widget.student,
            );
            return Column(
              children: [
                _buildAppBar(current),
                Expanded(child: _buildBody(current)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Built by hand rather than with [AppBar], as the class and attendance
  /// screens do, so it sits on the same background as the body. The frame
  /// titles it with the pupil's own name, not "Student Profile".
  Widget _buildAppBar(GB_Student current) {
    final void Function(GB_Student)? onMenu = widget.onMenu;

    return SizedBox(
      height: 64.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              color: kHomeIconColor,
              tooltip: "Back",
            ),
            Expanded(
              child: Text(
                current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: kClassAppBarTitleSize,
                  height: 28.0 / kClassAppBarTitleSize,
                  fontWeight: FontWeight.w500,
                  color: kHomeTitleTextColor,
                ),
              ),
            ),
            if (onMenu != null)
              IconButton(
                onPressed: () => onMenu(current),
                icon: const Icon(Icons.more_vert),
                color: kHomeIconColor,
                tooltip: "More options",
              )
            else
              const SizedBox(width: 48.0),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GB_Student current) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kSheetHorizontalPadding,
        8.0,
        kSheetHorizontalPadding,
        32.0,
      ),
      children: [
        _buildAvatar(current),
        const SizedBox(height: 24.0),
        _buildAttendanceCard(),
        const SizedBox(height: 24.0),
        _buildTabs(),
        const SizedBox(height: 20.0),
        if (_tab == _GB_ProfileTab.personal)
          _buildPersonalFields(current)
        else
          _buildAcademicsPlaceholder(),
      ],
    );
  }

  Widget _buildAvatar(GB_Student current) {
    return Center(
      child: CircleAvatar(
        radius: kStudentProfileAvatarRadius,
        // The tint shows through while a photo loads, and stands in for one
        // that has gone missing off the device.
        backgroundColor: kStudentAvatarTintColor,
        backgroundImage: current.photoPath == null
            ? AssetImage(current.imagePath) as ImageProvider
            : FileImage(File(current.photoPath!)),
      ),
    );
  }

  /// The frame's attendance card, on the server's own totals.
  ///
  /// Four states, because the card is the only part of this screen that can
  /// fail: loading, failed, recorded, and a pupil with no marks at all. The
  /// last is not drawn as 0% — the server returns null for the percentage
  /// precisely so that "no register taken yet" cannot be read as a child who
  /// never turned up.
  Widget _buildAttendanceCard() {
    final GB_AttendanceSummary? summary = _summary;
    final bool hasMarks = summary != null && summary.hasMarks;

    return Container(
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        border: Border.all(color: kHomeCardBorderColor),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Attendance",
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w600,
                    color: kTextColor,
                  ),
                ),
              ),
              if (hasMarks)
                Text(
                  "${_trimPercent(summary.percentPresent!)}%",
                  style: const TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w600,
                    color: kStudentProfileAttendanceColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(kPillButtonRadius),
            child: LinearProgressIndicator(
              // An indeterminate bar while loading, which is the one moment
              // the card has nothing true to show.
              value: _isLoadingSummary
                  ? null
                  : (hasMarks ? summary.percentPresent! / 100.0 : 0.0),
              minHeight: 8.0,
              backgroundColor: kStudentProfileAttendanceTrackColor,
              valueColor: const AlwaysStoppedAnimation<Color>(
                kStudentProfileAttendanceColor,
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            _attendanceCaption(summary),
            style: const TextStyle(
              fontSize: kStudentProfileFieldLabelSize,
              fontWeight: FontWeight.w500,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ],
      ),
    );
  }

  String _attendanceCaption(GB_AttendanceSummary? summary) {
    if (_isLoadingSummary) return "Loading attendance…";
    final String? error = _summaryError;
    if (error != null) return error;
    if (summary == null || !summary.hasMarks) {
      return "No attendance recorded yet";
    }
    return "Present ${summary.present} of ${summary.daysRecorded} days";
  }

  /// "90", not "90.0" — the frame shows a whole number, and the server already
  /// rounds to one decimal, so this only drops a trailing zero.
  String _trimPercent(double percent) {
    return percent == percent.roundToDouble()
        ? percent.round().toString()
        : percent.toString();
  }

  Widget _buildTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTab("Personal", _GB_ProfileTab.personal),
        const SizedBox(width: 16.0),
        _buildTab("Academics", _GB_ProfileTab.academics),
      ],
    );
  }

  Widget _buildTab(String label, _GB_ProfileTab tab) {
    final bool isSelected = _tab == tab;

    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        width: kStudentProfileTabWidth,
        height: kStudentProfileTabHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? kStudentProfileTabFillColor : kPrimaryColor2,
          border: Border.all(color: kStudentProfileTabBorderColor),
          borderRadius: BorderRadius.circular(kPillButtonRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? kStudentProfileAttendanceColor
                : kHomeSubtitleTextColor,
          ),
        ),
      ),
    );
  }

  /// The eight fields asked for, which are **not** the five the frame draws.
  ///
  /// The frame lists mother's name, father's name, guardian's name, address
  /// and date of birth. What is wanted here is name, age, both parents' names
  /// *and* mobile numbers, date of birth and gender — so the guardian block
  /// and the address are left out, and the numbers, the age and the gender are
  /// added. The register-student form stays the one place that shows
  /// everything `students` holds.
  ///
  /// Age is derived rather than stored: [GB_Student.ageYears] works it out
  /// from the date of birth, so it is right on every birthday with nothing
  /// having to rewrite a row. The date is shown beside it because a teacher
  /// checking a record wants what the age came from.
  Widget _buildPersonalFields(GB_Student current) {
    final GB_StudentContact? mother = current.mother;
    final GB_StudentContact? father = current.father;

    return Column(
      children: [
        _GB_StudentField(label: "Name", value: current.name),
        _GB_StudentField(label: "Age", value: "${current.ageYears()} years"),
        _GB_StudentField(label: "Mother's Name", value: mother?.name),
        _GB_StudentField(label: "Mother's Number", value: mother?.mobile),
        _GB_StudentField(label: "Father's Name", value: father?.name),
        _GB_StudentField(label: "Father's Number", value: father?.mobile),
        _GB_StudentField(
          label: "Date Of Birth",
          value: _formatDate(current.dateOfBirth),
        ),
        _GB_StudentField(label: "Gender", value: current.gender),
      ],
    );
  }

  Widget _buildAcademicsPlaceholder() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48.0),
      child: Text(
        "Academics is still being designed.",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: kStudentProfileFieldValueSize,
          color: kHomeSubtitleTextColor,
        ),
      ),
    );
  }

  /// "22/08/2020", as the frame writes it.
  ///
  /// Note this is **not** the "12 Apr 2021" the register-student form uses,
  /// which spells the month out so that it cannot be read the American way
  /// round. The frame is explicit, so it wins here; if the two should agree,
  /// this is the line to change.
  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, "0");
    return "${two(date.day)}/${two(date.month)}/${date.year}";
  }
}

/// One field of the profile: a small grey label with its value under it, and a
/// rule beneath separating it from the next.
///
/// An empty or null [value] leaves the value line blank, as the frame's
/// "Guardian's Name" row does, rather than writing "Not added yet" into it.
/// The label is still there, so the row reads as something nobody has filled
/// in — which is exactly what it is.
class _GB_StudentField extends StatelessWidget {
  const _GB_StudentField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final String text = value ?? "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12.0),
        Text(
          label,
          style: const TextStyle(
            fontSize: kStudentProfileFieldLabelSize,
            color: kHomeSubtitleTextColor,
          ),
        ),
        const SizedBox(height: 6.0),
        // Holds the row's height even when the value is blank, so an empty
        // field is the same size as a filled one and the rules stay evenly
        // spaced down the list.
        SizedBox(
          height: 20.0,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: kStudentProfileFieldValueSize,
              fontWeight: FontWeight.w600,
              color: kTextColor,
            ),
          ),
        ),
        const SizedBox(height: 12.0),
        const Divider(
          height: 1.0,
          thickness: 1.0,
          color: kStudentProfileFieldRuleColor,
        ),
      ],
    );
  }
}
