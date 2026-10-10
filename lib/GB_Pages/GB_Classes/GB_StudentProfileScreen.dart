import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// One pupil's profile, opened from the class screen's student list.
///
/// **Personal details only.** The academics half of the design is deliberately
/// not here: the tables it reads from are still being designed, and a section
/// wired to nothing would have to be rewritten once they exist.
///
/// Everything drawn here comes from the `students` row the teacher already
/// holds in [GB_StudentStore] — the roster read fills it — so opening a
/// profile costs no extra request and works offline once the class is loaded.
///
/// The fields are a deliberate subset of what `students` stores: the address,
/// the parents' email addresses and the whole guardian block are left out. The
/// register-student form remains the place to see or change all of it.
class GB_StudentProfileScreen extends StatelessWidget {
  const GB_StudentProfileScreen({super.key, required this.student});

  /// The pupil as the list had them, and the fallback when the store no longer
  /// does. A pupil removed while their profile is open keeps drawing the
  /// details that were already on screen rather than blanking out underneath
  /// the teacher.
  final GB_Student student;

  static Future<void> open(BuildContext context, GB_Student student) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (BuildContext context) =>
            GB_StudentProfileScreen(student: student),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      body: SafeArea(
        // Listening to the store rather than holding a copy: a pupil edited
        // from the list behind this screen is redrawn here without reopening.
        child: ValueListenableBuilder<List<GB_Student>>(
          valueListenable: GB_StudentStore.students,
          builder: (
            BuildContext context,
            List<GB_Student> students,
            Widget? child,
          ) {
            final GB_Student current = students.firstWhere(
              (GB_Student s) => s.studentId == student.studentId,
              orElse: () => student,
            );
            return Column(
              children: [
                _buildAppBar(context),
                Expanded(child: _buildBody(current)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Built by hand rather than with [AppBar], as the class and attendance
  /// screens do, so it sits on the same tinted background as the body.
  Widget _buildAppBar(BuildContext context) {
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
            const Expanded(
              child: Text(
                "Student Profile",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kClassAppBarTitleSize,
                  height: 28.0 / kClassAppBarTitleSize,
                  fontWeight: FontWeight.w500,
                  color: kHomeTitleTextColor,
                ),
              ),
            ),
            // Balances the back button so the title sits where it does on the
            // other screens, which centre it against a trailing action.
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
        _buildHeader(current),
        const SizedBox(height: 28.0),
        _buildSectionTitle("Personal Details"),
        const SizedBox(height: 12.0),
        _buildPersonalDetailsCard(current),
      ],
    );
  }

  Widget _buildHeader(GB_Student current) {
    return Column(
      children: [
        CircleAvatar(
          radius: 48.0,
          // The tint shows through while a photo loads, and stands in for one
          // that has gone missing off the device.
          backgroundColor: kStudentAvatarTintColor,
          backgroundImage: current.photoPath == null
              ? AssetImage(current.imagePath) as ImageProvider
              : FileImage(File(current.photoPath!)),
        ),
        const SizedBox(height: 14.0),
        Text(
          current.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: kStudentListNameTextSize,
            fontWeight: FontWeight.w600,
            color: kTextColor,
          ),
        ),
        if (current.rollNumber != null) ...[
          const SizedBox(height: 4.0),
          Text(
            "Roll No. ${current.rollNumber}",
            style: const TextStyle(
              fontSize: kStudentIdTextSize,
              fontWeight: FontWeight.w500,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: kClassAppBarTitleSize,
        fontWeight: FontWeight.w600,
        color: kHomeTitleTextColor,
      ),
    );
  }

  /// The eight fields this screen is for, in the order the design lists them.
  ///
  /// Age is worked out from the date of birth rather than stored, so it is
  /// right on every birthday without anything having to rewrite the row; both
  /// are shown because the design asks for the age and a teacher checking a
  /// record wants the date it came from.
  Widget _buildPersonalDetailsCard(GB_Student current) {
    final GB_StudentContact? mother = current.mother;
    final GB_StudentContact? father = current.father;

    return Container(
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        border: Border.all(color: kHomeCardBorderColor),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kClassTilePadding,
        vertical: 4.0,
      ),
      child: Column(
        children: [
          _GB_StudentDetailRow(
            icon: Icons.badge_outlined,
            label: "Name",
            value: current.name,
          ),
          _GB_StudentDetailRow(
            icon: Icons.cake_outlined,
            label: "Age",
            value: "${current.ageYears()} years",
          ),
          _GB_StudentDetailRow(
            icon: Icons.calendar_today_outlined,
            label: "Date of Birth",
            value: _formatDate(current.dateOfBirth),
          ),
          _GB_StudentDetailRow(
            icon: Icons.person_outline,
            label: "Gender",
            value: current.gender,
          ),
          _GB_StudentDetailRow(
            icon: Icons.woman_outlined,
            label: "Mother's Name",
            value: mother?.name,
          ),
          _GB_StudentDetailRow(
            icon: Icons.phone_outlined,
            label: "Mother's Number",
            value: mother?.mobile,
          ),
          _GB_StudentDetailRow(
            icon: Icons.man_outlined,
            label: "Father's Name",
            value: father?.name,
          ),
          _GB_StudentDetailRow(
            icon: Icons.phone_outlined,
            label: "Father's Number",
            value: father?.mobile,
            isLast: true,
          ),
        ],
      ),
    );
  }

  static const List<String> _monthNames = <String>[
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

  /// "12 Apr 2021" — day first, and a month name rather than a number, so it
  /// cannot be misread the way 04/12/2021 can. The same format the
  /// register-student form shows, so the two screens agree.
  static String _formatDate(DateTime date) {
    return "${date.day} ${_monthNames[date.month - 1]} ${date.year}";
  }
}

/// One labelled line of the personal-details card.
///
/// An empty or null [value] draws "Not added yet" in the muted colour instead
/// of an empty gap: the parents' details are optional on the register form, and
/// a blank row would read as a rendering fault rather than something nobody
/// filled in.
class _GB_StudentDetailRow extends StatelessWidget {
  const _GB_StudentDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// Suppresses the divider under the final row, which would otherwise draw a
  /// line along the inside of the card's own border.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final String? text = value;
    final bool isMissing = text == null || text.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: Row(
            children: [
              Icon(icon, size: 20.0, color: kHomeIconColor),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: kClassSubtitleTextSize,
                        color: kHomeSubtitleTextColor,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      isMissing ? "Not added yet" : text,
                      style: TextStyle(
                        fontSize: kEventSubtitleTextSize,
                        color: isMissing
                            ? kHomeSubtitleTextColor
                            : kHomeTitleTextColor,
                        fontStyle:
                            isMissing ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1.0,
            thickness: 1.0,
            color: kHomeCardBorderColor,
          ),
      ],
    );
  }
}
