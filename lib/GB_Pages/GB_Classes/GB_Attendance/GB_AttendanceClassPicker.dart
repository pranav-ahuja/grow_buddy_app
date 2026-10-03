import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_Attendance/GB_AttendanceWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The sheet "Mark Attendance" opens: pick the class whose register to take.
///
/// Returns the class picked, or null if the sheet was dismissed.
class GB_AttendanceClassPicker extends StatelessWidget {
  const GB_AttendanceClassPicker({
    super.key,
    required this.title,
    required this.classes,
    required this.countsFor,
  });

  final String title;
  final List<GB_ClassInfo> classes;
  final GB_AttendanceDayCounts Function(GB_ClassInfo) countsFor;

  static Future<GB_ClassInfo?> show(
    BuildContext context, {
    required String title,
    required List<GB_ClassInfo> classes,
    required GB_AttendanceDayCounts Function(GB_ClassInfo) countsFor,
  }) {
    return showModalBottomSheet<GB_ClassInfo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: kAttendanceSheetBarrierColor,
      builder: (BuildContext context) => GB_AttendanceClassPicker(
        title: title,
        classes: classes,
        countsFor: countsFor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.72;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSheetHorizontalPadding),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16.0,
                    height: 24.0 / 16.0,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.0256,
                    color: kAttendanceOutlineColor,
                  ),
                ),
              ),
              const SizedBox(height: 20.0),
              const Divider(
                height: 1.0,
                thickness: 1.0,
                indent: 16.0,
                endIndent: 16.0,
                color: kSheetHandleColor,
              ),
              Flexible(
                child: classes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          "No classes yet.",
                          style: TextStyle(color: kHomeSubtitleTextColor),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20.0, 31.0, 20.0, 0.0),
                        children: [
                          for (final GB_ClassInfo classInfo in classes)
                            GB_AttendanceClassCard(
                              classInfo: classInfo,
                              counts: countsFor(classInfo),
                              onTap: () =>
                                  Navigator.of(context).pop(classInfo),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
