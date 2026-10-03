import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Services/GB_AttendanceApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The pieces the attendance screens are built from, laid out after the Figma
/// frame `470-18042`. "Attendance" is spelt correctly throughout although the
/// design reads "Attendence" — the same call the bottom bar already makes.

const List<String> _monthNames = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// "03 Oct 2024", as the register's header shows the day.
String gFormatAttendanceDate(DateTime date) =>
    "${gTwoDigits(date.day)} ${_monthNames[date.month - 1]} ${date.year}";

/// The design writes every count and roll number with two digits: "P:05".
String gTwoDigits(int value) => value.toString().padLeft(2, "0");

/// Today as a calendar date, with no time of day to drift across midnight.
DateTime gToday() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// One class's day at a glance: how many pupils, and how many were marked
/// present and absent. Null counts mean the day could not be read.
class GB_AttendanceDayCounts {
  const GB_AttendanceDayCounts({
    required this.total,
    this.present,
    this.absent,
  });

  factory GB_AttendanceDayCounts.from({
    required int total,
    required GB_Register register,
  }) {
    final int present = register.values
        .where((GB_AttendanceStatus s) => s == GB_AttendanceStatus.present)
        .length;
    return GB_AttendanceDayCounts(
      total: total,
      present: present,
      absent: register.length - present,
    );
  }

  final int total;
  final int? present;
  final int? absent;

  /// "T:20 P:18 A:02". An unreadable day shows dashes rather than zeros —
  /// "P:00" would claim nobody came.
  String get caption {
    String count(int? value) => value == null ? "--" : gTwoDigits(value);
    return "T:${gTwoDigits(total)} P:${count(present)} A:${count(absent)}";
  }
}

/// The card at the top of the Attendance tab: the pitch, the action, and the
/// illustration.
class GB_MarkAttendanceCard extends StatelessWidget {
  const GB_MarkAttendanceCard({
    super.key,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kAttendanceCardHeight,
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        borderRadius: BorderRadius.circular(kClassTileRadius),
        border: Border.all(color: kAttendanceCardBorderColor),
        boxShadow: const [
          BoxShadow(
            color: kAttendanceCardShadowColor,
            blurRadius: 10.0,
            offset: Offset(4.0, 4.0),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 15.0,
            top: 0.0,
            bottom: 0.0,
            child: Center(
              // The design shows the artwork mirrored: the calendar on the
              // left, the man facing into the card.
              child: Transform.flip(
                flipX: true,
                child: Image.asset(
                  kAttendanceIllustration,
                  width: kAttendanceIllustrationSize,
                  height: kAttendanceIllustrationSize,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            left: 15.0,
            top: 0.0,
            bottom: 0.0,
            width: 156.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Track daily attendance and generate reports with a few "
                  "clicks",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: kEventSubtitleTextSize,
                    height: 24.0 / kEventSubtitleTextSize,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.021,
                    color: kHomeTitleTextColor,
                  ),
                ),
                const SizedBox(height: 20.0),
                SizedBox(
                  width: 152.0,
                  height: 32.0,
                  child: ElevatedButton(
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kHomeAccentColor,
                      foregroundColor: kPrimaryColor2,
                      elevation: 0.0,
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kClassTileRadius),
                      ),
                    ),
                    child: Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: kEventSubtitleTextSize,
                        height: 20.0 / kEventSubtitleTextSize,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
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

/// A class with today's counts and a chevron — the dashboard's class tile,
/// captioned "T:20 P:18 A:02".
class GB_AttendanceClassCard extends StatelessWidget {
  const GB_AttendanceClassCard({
    super.key,
    required this.classInfo,
    required this.counts,
    required this.onTap,
  });

  final GB_ClassInfo classInfo;
  final GB_AttendanceDayCounts counts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GB_ClassTile(
      classInfo: classInfo,
      subtitle: counts.caption,
      onTap: onTap,
      trailing: const Icon(
        Icons.chevron_right,
        size: 24.0,
        color: kHomeIconColor,
      ),
    );
  }
}

/// One of the two totals on a register: "18 Present", "02 Absent".
class GB_AttendanceCountBox extends StatelessWidget {
  const GB_AttendanceCountBox({
    super.key,
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66.0,
      height: 78.0,
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        borderRadius: BorderRadius.circular(kClassTileRadius),
        border: Border.all(color: kAttendanceOutlineColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 4.0,
            offset: Offset(0.0, 4.0),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            gTwoDigits(count),
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            label,
            style: const TextStyle(
              fontSize: kClassSubtitleTextSize,
              color: kHomeTitleTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pupil's mark: an empty box until marked, then a teal tick for present or
/// a red one for absent. A 40pt target around an 18pt box, as the design's
/// checkbox component draws it. Null [onTap] makes it read-only.
class GB_AttendanceStatusBox extends StatelessWidget {
  const GB_AttendanceStatusBox({
    super.key,
    required this.status,
    this.onTap,
  });

  final GB_AttendanceStatus? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color? fill = switch (status) {
      GB_AttendanceStatus.present => kAttendancePresentColor,
      GB_AttendanceStatus.absent => kAttendanceAbsentColor,
      null => null,
    };

    return Semantics(
      button: onTap != null,
      label: switch (status) {
        GB_AttendanceStatus.present => "Present",
        GB_AttendanceStatus.absent => "Absent",
        null => "Not marked",
      },
      child: InkResponse(
        onTap: onTap,
        radius: 20.0,
        child: SizedBox(
          width: kAttendanceTableRowHeight,
          height: kAttendanceTableRowHeight,
          child: Center(
            child: Container(
              width: 18.0,
              height: 18.0,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(2.0),
                border: fill == null
                    ? Border.all(color: kAttendanceOutlineColor, width: 2.0)
                    : null,
              ),
              child: fill == null
                  ? null
                  : const Icon(Icons.done, size: 18.0, color: kPrimaryColor2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed rule under the register's header row.
class GB_DashedDivider extends StatelessWidget {
  const GB_DashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 1.0,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter()),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  static const double _dash = 5.0;
  static const double _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = kAttendanceTableDividerColor
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    final double y = size.height / 2;
    for (double x = 0.5; x < size.width; x += _dash + _gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + _dash).clamp(0.0, size.width - 0.5), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
