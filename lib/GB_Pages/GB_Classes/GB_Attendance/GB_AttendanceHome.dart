import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_Attendance/GB_AttendanceClassPicker.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_Attendance/GB_AttendanceWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_Attendance/GB_MarkAttendanceScreen.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AttendanceApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The Attendance tab's app bar: back to Home, and the tab's name.
class GB_AttendanceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const GB_AttendanceAppBar({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: kPrimaryColor2,
      surfaceTintColor: kPrimaryColor2,
      elevation: 0.0,
      toolbarHeight: 64.0,
      // The design's 4pt bar padding plus a 48pt icon button.
      leadingWidth: 52.0,
      leading: IconButton(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
        color: kHomeIconColor,
        tooltip: "Back",
      ),
      titleSpacing: 0.0,
      title: const Text(
        "Attendance",
        style: TextStyle(
          fontSize: kClassAppBarTitleSize,
          height: 28.0 / kClassAppBarTitleSize,
          fontWeight: FontWeight.w500,
          color: kHomeTitleTextColor,
        ),
      ),
    );
  }
}

/// The body of the dashboard's Attendance tab: the "Mark Attendance" card and
/// every class with today's counts.
///
/// The classes and pupils come from the dashboard's stores; this screen reads
/// only today's register for each class, to count who is present and absent.
class GB_AttendanceHome extends StatefulWidget {
  const GB_AttendanceHome({super.key});

  @override
  State<GB_AttendanceHome> createState() => _GB_AttendanceHomeState();
}

class _GB_AttendanceHomeState extends State<GB_AttendanceHome>
    with WidgetsBindingObserver {
  /// Today's register per class. A class missing here could not be read.
  Map<String, GB_Register> _today = {};

  bool get _canMark => gIsTeacher();

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

  /// Reloads when the app comes back to the foreground.
  ///
  /// [_refresh] reads [gToday] afresh, so this is also what carries the tab
  /// over midnight: an app left open overnight would otherwise still be
  /// showing yesterday's counts, and every class would read as already
  /// marked on a day nobody had marked yet.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Reads today's register for every class, side by side.
  Future<void> _refresh() async {
    final List<GB_ClassInfo> classes = GB_ClassStore.classes.value;
    final DateTime today = gToday();
    final String token = gRequireToken();

    final Map<String, GB_Register> registers = {};
    String? failure;
    await Future.wait(
      classes.map((GB_ClassInfo classInfo) async {
        try {
          registers[classInfo.id] = await GB_AttendanceApi.classRegister(
            token: token,
            classId: classInfo.id,
            date: today,
          );
        } on GB_ApiException catch (error) {
          failure ??= error.message;
        }
      }),
    );

    if (!mounted) return;
    setState(() => _today = registers);
    if (failure != null) gShowSnack(context, failure!);
  }

  GB_AttendanceDayCounts _countsFor(GB_ClassInfo classInfo) {
    final int total = GB_StudentStore.countInClass(classInfo.id);
    final GB_Register? register = _today[classInfo.id];
    return register == null
        ? GB_AttendanceDayCounts(total: total)
        : GB_AttendanceDayCounts.from(total: total, register: register);
  }

  Future<void> _openRegister(GB_ClassInfo classInfo) async {
    final bool? saved = await GB_MarkAttendanceScreen.open(context, classInfo);
    if (saved == true && mounted) await _refresh();
  }

  /// "Mark Attendance" → pick a class → its register → back to the picker.
  ///
  /// The sheet reopens after each register, carrying the counts the save just
  /// changed, because a teacher takes one class after another. Dismissing the
  /// sheet is what ends the round.
  Future<void> _pickClass() async {
    while (true) {
      final GB_ClassInfo? picked = await GB_AttendanceClassPicker.show(
        context,
        title: _canMark
            ? "Select Class and Mark Attendance"
            : "Select Class to View Attendance",
        classes: GB_ClassStore.classes.value,
        countsFor: _countsFor,
      );
      if (picked == null || !mounted) return;
      await _openRegister(picked);
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: kHomeAccentColor,
      child: ValueListenableBuilder<List<GB_ClassInfo>>(
        valueListenable: GB_ClassStore.classes,
        builder: (BuildContext context, List<GB_ClassInfo> classes, _) {
          return ValueListenableBuilder<List<GB_Student>>(
            valueListenable: GB_StudentStore.students,
            builder: (BuildContext context, _, __) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                kHomeHorizontalPadding,
                32.0,
                kHomeHorizontalPadding,
                24.0,
              ),
              children: [
                GB_MarkAttendanceCard(
                  buttonLabel: _canMark ? "Mark Attendance" : "View Attendance",
                  onPressed: _pickClass,
                ),
                const SizedBox(height: 32.0),
                Text(
                  _canMark ? "Review or Edit Attendance" : "Review Attendance",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: kHomeSectionHeaderTextSize,
                    height: 28.0 / kHomeSectionHeaderTextSize,
                    fontWeight: FontWeight.w500,
                    color: kHomeTitleTextColor,
                  ),
                ),
                const SizedBox(height: 24.0),
                if (classes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text(
                      "No classes yet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kHomeSubtitleTextColor),
                    ),
                  )
                else
                  for (final GB_ClassInfo classInfo in classes)
                    GB_AttendanceClassCard(
                      classInfo: classInfo,
                      counts: _countsFor(classInfo),
                      onTap: () => _openRegister(classInfo),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
