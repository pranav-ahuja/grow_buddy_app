import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentFormFields.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The class screen's "See All": every pupil in one class, searchable by name.
///
/// A sheet rather than a page, because it is the students row opened out — the
/// class stays behind it, and dismissing puts the teacher back where they were.
/// It shares the attendance picker's chrome (grabber, centred head, rule, then
/// the list) because the design draws them as the same component.
///
/// The list is built from [GB_StudentStore], so a pupil edited or removed
/// while the sheet is open is redrawn here without reopening it.
class GB_StudentListSheet extends StatefulWidget {
  const GB_StudentListSheet({
    super.key,
    required this.classInfo,
    this.onAddStudent,
    this.onStudentTap,
    this.onStudentLongPress,
  });

  final GB_ClassInfo classInfo;

  /// Shown as the sheet's "Add Student" button. Null draws no button, which is
  /// how a parent's account sees the list — read-only, as on the class screen.
  final VoidCallback? onAddStudent;

  final void Function(GB_Student)? onStudentTap;

  /// Held down to edit the pupil, exactly as on the class screen's cards.
  final void Function(GB_Student)? onStudentLongPress;

  /// Opens the sheet. The callbacks run after it closes, so the screen beneath
  /// is the one that owns the form or the menu they open.
  static Future<void> show(
    BuildContext context, {
    required GB_ClassInfo classInfo,
    VoidCallback? onAddStudent,
    void Function(GB_Student)? onStudentTap,
    void Function(GB_Student)? onStudentLongPress,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: kAttendanceSheetBarrierColor,
      builder: (BuildContext context) => GB_StudentListSheet(
        classInfo: classInfo,
        onAddStudent: onAddStudent,
        onStudentTap: onStudentTap,
        onStudentLongPress: onStudentLongPress,
      ),
    );
  }

  @override
  State<GB_StudentListSheet> createState() => _GB_StudentListSheetState();
}

class _GB_StudentListSheetState extends State<GB_StudentListSheet> {
  final TextEditingController _search = TextEditingController();

  /// What has been typed, folded to lower case once rather than per pupil.
  String _query = "";

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// In roll-number order, narrowed to the search. Matching on name alone is
  /// what the design's field asks for; the roll number is on screen anyway.
  List<GB_Student> get _matches {
    final List<GB_Student> students =
        GB_StudentStore.inClass(widget.classInfo.id);
    if (_query.isEmpty) return students;
    return students
        .where((GB_Student s) => s.name.toLowerCase().contains(_query))
        .toList();
  }

  /// Closes first, so the form or menu the callback opens is not stacked on a
  /// sheet that is about to be dismissed behind it.
  void _closeThen(void Function() action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double maxHeight = media.size.height * 0.72;

    return Padding(
      // viewInsets, not viewPadding: this is the keyboard's height, and the
      // sheet has to clear it. Without this the keyboard opens over the list
      // — the half of the sheet the search exists to narrow — and the sheet
      // stays its full height underneath it. Lifting it also shortens it,
      // because the constraint this sits inside is what is left above the
      // keyboard, so the list below keeps whatever room is spare.
      padding: EdgeInsets.only(
        left: kSheetHorizontalPadding,
        right: kSheetHorizontalPadding,
        bottom: media.viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight < kAttendanceSheetMaxHeight
              ? maxHeight
              : kAttendanceSheetMaxHeight,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: kPrimaryColor2,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(kSheetTopRadius),
            ),
            border: Border(
              top: BorderSide(color: kAttendanceSheetBorderColor),
              left: BorderSide(color: kAttendanceSheetBorderColor),
              right: BorderSide(color: kAttendanceSheetBorderColor),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 15.0),
              Container(
                width: 32.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: kAttendanceSheetGrabberColor,
                  borderRadius: BorderRadius.circular(kPillButtonRadius),
                ),
              ),
              const SizedBox(height: 32.0),
              _buildSearchField(),
              const SizedBox(height: 20.0),
              // The design's "Indicator" rule, which is the field's underline.
              const Divider(
                height: 1.0,
                thickness: 1.0,
                indent: 16.0,
                endIndent: 16.0,
                color: kSheetHandleColor,
              ),
              Flexible(child: _buildList()),
              if (widget.onAddStudent != null) ...[
                const SizedBox(height: 16.0),
                SizedBox(
                  width: 237.0,
                  child: GB_PillButton(
                    label: "Add Student",
                    onPressed: () => _closeThen(widget.onAddStudent!),
                  ),
                ),
              ],
              const SizedBox(height: 24.0),
            ],
          ),
        ),
      ),
    );
  }

  /// The head of the sheet is the search box: the design sets its placeholder
  /// in the title's own position and style, with the rule beneath standing in
  /// for the underline, so an empty field reads as the sheet's heading.
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TextField(
        controller: _search,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.search,
        onChanged: (String value) =>
            setState(() => _query = value.trim().toLowerCase()),
        style: const TextStyle(
          fontSize: kSheetIntroTextSize,
          height: 24.0 / kSheetIntroTextSize,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.0256,
          color: kHomeTitleTextColor,
        ),
        cursorColor: kHomeAccentColor,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: "Search Student's Name",
          hintStyle: const TextStyle(
            fontSize: kSheetIntroTextSize,
            height: 24.0 / kSheetIntroTextSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.0256,
            color: kAttendanceOutlineColor,
          ),
          // Only once there is something to clear, so the empty field keeps
          // the centred heading the design draws.
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18.0),
                  color: kAttendanceOutlineColor,
                  tooltip: "Clear search",
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = "");
                  },
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 32.0,
            minHeight: 24.0,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ValueListenableBuilder<List<GB_Student>>(
      valueListenable: GB_StudentStore.students,
      builder: (BuildContext context, List<GB_Student> _, __) {
        final List<GB_Student> students = _matches;

        if (students.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              _query.isEmpty
                  ? "No students in this class yet."
                  : "No student's name matches that.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: kEventSubtitleTextSize,
                color: kHomeSubtitleTextColor,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20.0, 31.0, 20.0, 0.0),
          itemCount: students.length,
          itemBuilder: (BuildContext context, int index) {
            final GB_Student student = students[index];
            return GB_StudentListRow(
              student: student,
              onTap: widget.onStudentTap == null
                  ? null
                  : () => _closeThen(() => widget.onStudentTap!(student)),
              onLongPress: widget.onStudentLongPress == null
                  ? null
                  : () => _closeThen(() => widget.onStudentLongPress!(student)),
            );
          },
        );
      },
    );
  }
}

/// One pupil as the design's list draws them: the round photo, then the name.
///
/// The roll number sits under the name — it is what a teacher calls a pupil
/// by, and the one thing that tells two children of the same name apart. The
/// design's row carries a name only, which a class register cannot afford.
class GB_StudentListRow extends StatelessWidget {
  const GB_StudentListRow({
    super.key,
    required this.student,
    this.onTap,
    this.onLongPress,
  });

  final GB_Student student;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(kClassTileRadius),
      child: SizedBox(
        height: kStudentListRowHeight,
        child: Row(
          children: [
            CircleAvatar(
              radius: kStudentListAvatarRadius,
              // The tint shows through while a photo loads, and stands in for
              // one that has gone missing off the device.
              backgroundColor: kStudentAvatarTintColor,
              backgroundImage: student.photoPath == null
                  ? AssetImage(student.imagePath) as ImageProvider
                  : FileImage(File(student.photoPath!)),
            ),
            const SizedBox(width: kStudentListAvatarGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kStudentListNameTextSize,
                      fontWeight: FontWeight.w500,
                      color: kTextColor,
                    ),
                  ),
                  if (student.rollNumber != null)
                    Text(
                      "Roll No. ${student.rollNumber}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: kStudentIdTextSize,
                        fontWeight: FontWeight.w500,
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
}
