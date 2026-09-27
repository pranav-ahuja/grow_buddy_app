import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_TeacherApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// "Add teacher" — the principal choosing who takes a class.
///
/// Opened from the class screen's floating button, which only the principal
/// has. A list of the school's teachers; **tapping one highlights it**, and as
/// many can be highlighted as belong in the room. The sheet opens with whoever
/// already teaches the class picked, so it shows the current answer rather
/// than an empty form the principal has to rebuild from memory.
///
/// **It sends the whole set, not a difference.** That is the contract of
/// `PUT /classes/{id}/teachers` and it is the right one here: a screen of
/// highlighted names knows what it wants the answer to be, and asking it to
/// work out what changed is how an unhighlighted teacher stays assigned. It
/// also means un-picking everyone is a real instruction — the class becomes
/// unassigned, which is the state it was created in.
///
/// The **class teacher** — the one answerable for the room — is preserved by
/// the server as long as they are still picked. Tapping names in a different
/// order cannot move that role, which is why the sheet does not ask about it.
///
/// Teachers sign themselves up; this does not create accounts. A teacher who
/// has not registered yet is not in the list, and the empty state says so.
///
/// Call [show]; it returns the class as it now stands, or null if the sheet
/// was dismissed.
class GB_AddTeacherSheet extends StatefulWidget {
  const GB_AddTeacherSheet({super.key, required this.classInfo});

  final GB_ClassInfo classInfo;

  static Future<GB_ClassInfo?> show(
    BuildContext context, {
    required GB_ClassInfo classInfo,
  }) {
    return showModalBottomSheet<GB_ClassInfo>(
      context: context,
      backgroundColor: kPrimaryColor2,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kClassPanelRadius),
        ),
      ),
      builder: (BuildContext context) =>
          GB_AddTeacherSheet(classInfo: classInfo),
    );
  }

  @override
  State<GB_AddTeacherSheet> createState() => _GB_AddTeacherSheetState();
}

class _GB_AddTeacherSheetState extends State<GB_AddTeacherSheet> {
  /// The school's teachers. Null while they are on their way.
  List<GB_TeacherSummary>? _teachers;

  /// Who is picked. A set, because the only questions asked of it are "is this
  /// one in?" and "what is the whole answer?".
  ///
  /// Seeded from the class as it stands, so the sheet opens showing the truth.
  late Set<String> _picked = widget.classInfo.teacherIds.toSet();

  String? _loadError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<GB_TeacherSummary> teachers =
          await GB_TeacherApi.listTeachers(token: gRequireToken());
      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _loadError = null;
      });
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.message);
    }
  }

  void _toggle(String teacherId) {
    setState(() {
      if (!_picked.remove(teacherId)) _picked.add(teacherId);
    });
  }

  /// True when the highlighted set is the one the class already has.
  ///
  /// Saving then would be a round trip that changes nothing, so the button is
  /// disabled — and, more usefully, the principal can see at a glance whether
  /// they have actually changed anything.
  bool get _isUnchanged {
    final Set<String> current = widget.classInfo.teacherIds.toSet();
    return current.length == _picked.length && current.containsAll(_picked);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // The class teacher goes first so that a class with no owner gets a
      // sensible one — the server takes the first id for a class that has
      // none, and keeps the sitting class teacher for one that has.
      final List<String> ordered = <String>[
        if (widget.classInfo.teacherId != null &&
            _picked.contains(widget.classInfo.teacherId))
          widget.classInfo.teacherId!,
        ..._picked.where(
          (String id) => id != widget.classInfo.teacherId,
        ),
      ];

      final GB_ClassInfo updated =
          await GB_ClassStore.setTeachers(widget.classInfo.id, ordered);

      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      // The likeliest refusal is a name clash — the receiving teacher already
      // has a class called this. The server's message names them, so it is
      // shown as-is rather than summarised.
      setState(() {
        _loadError = error.message;
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12.0),
          Center(
            child: Container(
              width: 32.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: kHomeNavBorderColor,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 0.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Add teacher",
                  style: TextStyle(
                    fontSize: kClassAppBarTitleSize,
                    fontWeight: FontWeight.w500,
                    color: kHomeTitleTextColor,
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  "Choose who teaches ${widget.classInfo.name}. "
                  "You can pick more than one.",
                  style: const TextStyle(
                    fontSize: kEventSubtitleTextSize,
                    height: 1.4,
                    color: kHomeSubtitleTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16.0),
          // Capped so the sheet cannot grow past the screen on a school with
          // forty teachers; the list scrolls inside it.
          Flexible(child: _buildList()),
          _buildFooter(screenWidth),
        ],
      ),
    );
  }

  Widget _buildList() {
    final String? error = _loadError;
    final List<GB_TeacherSummary>? teachers = _teachers;

    if (teachers == null && error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: CircularProgressIndicator(color: kHomeAccentColor),
        ),
      );
    }

    if (teachers == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 8.0),
        child: Column(
          children: [
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: kEventSubtitleTextSize,
                height: 1.4,
                color: kHomeSubtitleTextColor,
              ),
            ),
            const SizedBox(height: 12.0),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(foregroundColor: kHomeAccentColor),
              child: const Text("Try again"),
            ),
          ],
        ),
      );
    }

    if (teachers.isEmpty) {
      // Teachers register themselves, so an empty list is a school where
      // nobody has signed up yet — not a failure, and not something the
      // principal can fix from here.
      return const Padding(
        padding: EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 16.0),
        child: Text(
          "No teachers have signed up yet. Once they register on the app "
          "they'll appear here.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: kEventSubtitleTextSize,
            height: 1.4,
            color: kHomeSubtitleTextColor,
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      itemCount: teachers.length,
      itemBuilder: (BuildContext context, int index) {
        final GB_TeacherSummary teacher = teachers[index];
        return _buildTeacherTile(teacher, _picked.contains(teacher.teacherId));
      },
    );
  }

  /// One teacher, highlighted when picked.
  ///
  /// The highlight is a tinted fill plus a coloured border and a tick — three
  /// signals rather than colour alone, so it still reads for someone who
  /// cannot tell the tinted row from the plain one.
  Widget _buildTeacherTile(GB_TeacherSummary teacher, bool isPicked) {
    final bool isClassTeacher = teacher.teacherId == widget.classInfo.teacherId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: _isSaving ? null : () => _toggle(teacher.teacherId),
        borderRadius: BorderRadius.circular(kClassTileRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12.0,
            vertical: 12.0,
          ),
          decoration: BoxDecoration(
            color: isPicked ? kClassTileGreenFill : null,
            borderRadius: BorderRadius.circular(kClassTileRadius),
            border: Border.all(
              color: isPicked ? kClassTileGreenBorder : kHomeNavBorderColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isPicked
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: kClassDeleteIconSize,
                color: isPicked ? kHomeAccentColor : kHomeSubtitleTextColor,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            teacher.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kEventSubtitleTextSize,
                              fontWeight: isPicked
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: kHomeTitleTextColor,
                            ),
                          ),
                        ),
                        if (isClassTeacher) ...[
                          const SizedBox(width: 8.0),
                          // Named, because un-picking this one does not just
                          // remove a teacher — it leaves the room without
                          // anyone answerable for it.
                          const Text(
                            "Class teacher",
                            style: TextStyle(
                              fontSize: kFieldLabelTextSize,
                              color: kHomeAccentColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      // What they already teach, or a contact. Two teachers
                      // can share a name, and the moment they do, a list of
                      // bare names is how the wrong one gets assigned.
                      teacher.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  Widget _buildFooter(double screenWidth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _picked.isEmpty
                // Said plainly rather than refused. A class with nobody on it
                // is a real state, and the principal may well mean it.
                ? "Nobody picked — the class will be left unassigned."
                : "${_picked.length} picked",
            style: const TextStyle(
              fontSize: kFieldLabelTextSize,
              color: kHomeSubtitleTextColor,
            ),
          ),
          const SizedBox(height: 10.0),
          SizedBox(
            width: double.infinity,
            child: GB_ElevatedButtonString(
              screenWidth: screenWidth,
              horizontalPadding: 0.0,
              verticalPadding: kElevatedButtonVerticalPadding,
              elevatedButtonText: _isSaving ? "Saving…" : "Save",
              buttonColor: kHomeAccentColor,
              elevatedButtonTextColor: kPrimaryColor2,
              elevatedButtonFontWeight: FontWeight.w500,
              elevatedButtonTextSize: kElevatedButtonTextSize,
              onPressed: _isSaving || _isUnchanged ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
