import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_Attendance/GB_AttendanceWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentFormFields.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AttendanceApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// One class's register for one day — the design's "Mark Attendance" screen.
///
/// Opens on today, already showing whatever was saved for it, so the same
/// screen takes a register and corrects one. Tapping the date reviews or
/// corrects an earlier day.
///
/// A box cycles empty → present → absent → present. The register is saved in
/// one request, and only once every pupil is marked: a half-marked day reads
/// later as "the rest were absent", which is a claim nobody made.
///
/// **The principal reads, and does not mark**, as on the server: the boxes
/// do nothing for them and there is no submit button.
///
/// Pops `true` after a save, so the caller can refresh its counts.
class GB_MarkAttendanceScreen extends StatefulWidget {
  const GB_MarkAttendanceScreen({super.key, required this.classInfo});

  final GB_ClassInfo classInfo;

  static Future<bool?> open(BuildContext context, GB_ClassInfo classInfo) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (BuildContext context) =>
            GB_MarkAttendanceScreen(classInfo: classInfo),
      ),
    );
  }

  @override
  State<GB_MarkAttendanceScreen> createState() =>
      _GB_MarkAttendanceScreenState();
}

class _GB_MarkAttendanceScreenState extends State<GB_MarkAttendanceScreen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  DateTime _date = gToday();

  /// True while the screen is showing today rather than a day the teacher
  /// went looking for. Only a screen that is following today rolls forward
  /// at midnight — one deliberately opened on an earlier day stays put.
  bool _followsToday = true;

  /// What the server holds for [_date], and what is on screen now.
  GB_Register _saved = {};
  GB_Register _marks = {};

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;

  /// Teachers mark; the principal reads.
  bool get _canMark => gIsTeacher();

  /// In roll-number order, which is the order the paper register is in.
  List<GB_Student> get _students =>
      GB_StudentStore.inClass(widget.classInfo.id);

  bool get _isDirty {
    if (_marks.length != _saved.length) return true;
    return _marks.entries.any((e) => _saved[e.key] != e.value);
  }

  int _count(GB_AttendanceStatus status) =>
      _marks.values.where((GB_AttendanceStatus s) => s == status).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  /// Carries the register over midnight when the app comes back.
  ///
  /// [_date] is read once, when the screen opens. An app left open overnight
  /// would still be on yesterday, and the next box tapped would file today's
  /// mark against yesterday's row — silently, because the screen looks right.
  /// A register is one day's by definition, so a new day starts over with
  /// nothing marked, which is what the empty boxes mean.
  ///
  /// Unsaved marks are never thrown away by the clock. The day they belong to
  /// is named instead, and submitting or discarding them stays the teacher's
  /// call — rolling the date under them would silently re-file work they had
  /// already done.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_followsToday) return;

    final DateTime today = gToday();
    if (today == _date) return;

    if (_isDirty) {
      gShowSnack(
        context,
        "It is now ${gFormatAttendanceDate(today)}. These marks are still for "
        "${gFormatAttendanceDate(_date)} — submit or discard them first.",
      );
      return;
    }

    setState(() => _date = today);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final GB_Register register = await GB_AttendanceApi.classRegister(
        token: gRequireToken(),
        classId: widget.classInfo.id,
        date: _date,
      );
      if (!mounted) return;
      setState(() {
        _saved = register;
        _marks = Map.of(register);
        _isLoading = false;
      });
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.message;
      });
    }
  }

  void _toggle(String studentId) {
    setState(() {
      _marks[studentId] = _marks[studentId] == GB_AttendanceStatus.present
          ? GB_AttendanceStatus.absent
          : GB_AttendanceStatus.present;
    });
  }

  void _markEveryonePresent() {
    setState(() {
      for (final GB_Student student in _students) {
        _marks[student.studentId] = GB_AttendanceStatus.present;
      }
    });
  }

  /// Asks before throwing away marks that were never saved.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            backgroundColor: kPrimaryColor2,
            title: const Text("Discard these marks?"),
            content: const Text(
              "The attendance you have marked has not been submitted.",
              style: TextStyle(
                fontSize: kEventSubtitleTextSize,
                height: 1.4,
                color: kHomeSubtitleTextColor,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Keep marking"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text("Discard"),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _pickDate() async {
    final DateTime today = gToday();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
      helpText: "Attendance for",
    );
    if (picked == null || picked == _date || !mounted) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      _date = picked;
      // Picking today puts the screen back on the day that rolls forward;
      // picking any earlier day pins it there until the teacher says
      // otherwise.
      _followsToday = picked == today;
    });
    await _load();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final List<GB_Student> students = _students;
    final int unmarked = students
        .where((GB_Student s) => !_marks.containsKey(s.studentId))
        .length;
    if (unmarked > 0) {
      gShowSnack(
        context,
        "Mark every pupil before submitting — $unmarked "
        "${unmarked == 1 ? "is" : "are"} still unmarked",
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await GB_AttendanceApi.submitRegister(
        token: gRequireToken(),
        classId: widget.classInfo.id,
        date: _date,
        marks: {
          for (final GB_Student s in students) s.studentId: _marks[s.studentId]!,
        },
      );
      if (!mounted) return;
      gShowSnack(
        context,
        "Attendance saved for ${widget.classInfo.name}, "
        "${gFormatAttendanceDate(_date)}",
      );
      _saved = Map.of(_marks);
      Navigator.of(context).pop(true);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      gShowSnack(context, error.message);
    }
  }

  Color get _panelColor => GB_ClassPalette.panelAt(
        GB_ClassPalette.slotForFill(widget.classInfo.fillColor),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _marks = Map.of(_saved);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: kPrimaryColor2,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 32.0),
              Text(
                _canMark ? "Review or Edit Attendance" : "Review Attendance",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16.0,
                  height: 28.0 / 16.0,
                  fontWeight: FontWeight.w500,
                  color: kHomeTitleTextColor,
                ),
              ),
              const SizedBox(height: 24.0),
              Expanded(child: _buildTable()),
              if (_canMark && !_isLoading && _loadError == null &&
                  _students.isNotEmpty)
                SizedBox(
                  width: 237.0,
                  child: GB_PillButton(
                    label: "Confirm & Submit Attendance",
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The tinted panel with the app bar and the day, and the two totals
  /// straddling its bottom edge as the design draws them.
  Widget _buildHeader() {
    const double panelHeight = 174.0;
    const double totalsTop = 133.0;
    const double totalsHeight = 81.0;

    return SizedBox(
      height: totalsTop + totalsHeight,
      child: Stack(
        children: [
          Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            height: panelHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _panelColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(kClassPanelRadius),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            child: _buildAppBar(),
          ),
          Positioned(
            top: 97.0,
            left: 0.0,
            right: 0.0,
            child: Center(
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    gFormatAttendanceDate(_date),
                    style: const TextStyle(
                      fontSize: 16.0,
                      height: 28.0 / 16.0,
                      color: kHomeTitleTextColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: totalsTop,
            left: 0.0,
            right: 0.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GB_AttendanceCountBox(
                  count: _count(GB_AttendanceStatus.present),
                  label: "Present",
                  color: kAttendancePresentColor,
                ),
                const SizedBox(width: 8.0),
                GB_AttendanceCountBox(
                  count: _count(GB_AttendanceStatus.absent),
                  label: "Absent",
                  color: kAttendanceAbsentColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
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
                widget.classInfo.name,
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
            if (_canMark)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                iconColor: kHomeIconColor,
                tooltip: "More options",
                color: kPrimaryColor2,
                onSelected: (String value) {
                  if (value == "all_present") _markEveryonePresent();
                },
                itemBuilder: (BuildContext context) => const [
                  PopupMenuItem<String>(
                    value: "all_present",
                    child: Text("Mark everyone present"),
                  ),
                ],
              )
            else
              const SizedBox(width: 48.0),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kHomeHorizontalPadding),
      decoration: const BoxDecoration(
        color: kPrimaryColor2,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kClassTileRadius),
        ),
        border: Border(
          top: BorderSide(color: kAttendanceCardBorderColor, width: 0.5),
          left: BorderSide(color: kAttendanceCardBorderColor, width: 0.5),
          right: BorderSide(color: kAttendanceCardBorderColor, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 43.0,
            child: _buildRow(
              roll: const Text("Roll No.", style: _cellStyle),
              name: const Text("Student's Name", style: _cellStyle),
              status: const Text("Status", style: _cellStyle),
            ),
          ),
          const GB_DashedDivider(),
          Expanded(child: _buildRows()),
        ],
      ),
    );
  }

  Widget _buildRows() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kHomeAccentColor),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kHomeSubtitleTextColor),
              ),
              const SizedBox(height: 12.0),
              OutlinedButton(
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHomeAccentColor,
                ),
                child: const Text("Try again"),
              ),
            ],
          ),
        ),
      );
    }

    final List<GB_Student> students = _students;
    if (students.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            "No students in this class yet.",
            style: TextStyle(color: kHomeSubtitleTextColor),
          ),
        ),
      );
    }

    return RawScrollbar(
      controller: _scroll,
      thumbColor: kAttendanceScrollbarColor,
      thickness: 4.0,
      radius: const Radius.circular(2.0),
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: students.length,
        itemExtent: kAttendanceTableRowHeight,
        itemBuilder: (BuildContext context, int index) {
          final GB_Student student = students[index];
          return _buildRow(
            roll: Text(
              student.rollNumber == null ? "--" : gTwoDigits(student.rollNumber!),
              style: _cellStyle,
            ),
            name: Text(
              student.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _cellStyle,
            ),
            status: GB_AttendanceStatusBox(
              status: _marks[student.studentId],
              onTap: _canMark && !_isSubmitting
                  ? () => _toggle(student.studentId)
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// The table's three columns: roll number, name, status — spaced as the
  /// design's 328pt table, with the name taking whatever is left.
  Widget _buildRow({
    required Widget roll,
    required Widget name,
    required Widget status,
  }) {
    return Row(
      children: [
        const SizedBox(width: 12.0),
        SizedBox(width: 61.0, child: Center(child: roll)),
        const SizedBox(width: 14.0),
        Expanded(child: Center(child: name)),
        SizedBox(width: 56.0, child: Center(child: status)),
        const SizedBox(width: 16.0),
      ],
    );
  }

  static const TextStyle _cellStyle = TextStyle(
    fontSize: kEventSubtitleTextSize,
    fontWeight: FontWeight.w500,
    color: kHomeTitleTextColor,
  );
}
