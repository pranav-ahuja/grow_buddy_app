import 'dart:async';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_AddTeacherSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassDialogs.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_NotificationStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
// GB_Event and GB_EventCard live with the home screen because that is where
// they first appeared; the class screen shows the same card for the events of
// one class, so it reuses them rather than growing a near-identical copy.
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The screen behind a class tile on the teacher's dashboard.
///
/// Layout follows the Figma frame `360-45584`: a tinted header panel carrying
/// the class's own colour with its events carousel, then the horizontally
/// scrolling "Features" row, then "Students list" with a "See All" link.
///
/// The events carousel is still placeholder data — [_events] is the seam to
/// replace when there is an events endpoint. The class, its teachers and its
/// students are real.
///
/// **Staff get a floating "Add student" button**, which opens the register
/// form with this class preselected. **The principal also gets "Add
/// teacher"**, and nobody else does. Choosing who takes a class is an administrator's act on a class
/// that already exists, which is why it lives on the class rather than in the
/// add-class form — a class is handed over and shared far more often than it
/// is created.
///
/// Holding a student card offers Edit or Cancel. Edit opens the pupil's
/// details, saved outright; Delete sits inside that form. What a delete does
/// depends on who asked: the principal's takes effect, a teacher's becomes a
/// request for the principal. The screen does not decide
/// that and does not need to — the server says which happened, in a sentence
/// this screen shows as-is.
class GB_ClassScreen extends StatefulWidget {
  const GB_ClassScreen({super.key, required this.classInfo});

  final GB_ClassInfo classInfo;

  @override
  State<GB_ClassScreen> createState() => _GB_ClassScreenState();
}

class _GB_ClassScreenState extends State<GB_ClassScreen> {
  int _activeEvent = 0;

  /// Only the principal chooses who teaches a class. As everywhere else, this
  /// governs what is **offered**: the server refuses a teacher's attempt
  /// regardless, so a wrong answer here costs a button, not a permission.
  bool get _canAssignTeachers => gIsPrincipal();

  /// Staff register pupils; a parent never reaches this screen, but the
  /// server refuses them regardless.
  bool get _canRegisterStudents => gIsPrincipal() || gIsTeacher();

  /// This screen's copy of the class, kept in state because it can be renamed
  /// from here.
  ///
  /// [GB_ClassInfo] is immutable, so a rename produces a new instance rather
  /// than changing the one this screen was handed — without this the app bar
  /// would keep showing the old name until the screen was left and reopened.
  late GB_ClassInfo _classInfo = widget.classInfo;

  /// A getter rather than a `late final` list: the subtitles carry the class
  /// name, so renaming the class has to change them too.
  List<GB_Event> get _events => [
        GB_Event(
          title: "Drawing Competition",
          subtitle: "Classes: ${_classInfo.name}",
          imagePath: kEventImage,
        ),
        GB_Event(
          title: "Sports Day",
          subtitle: "Classes: ${_classInfo.name}",
          imagePath: kEventImage,
        ),
      ];

  Future<void> _registerStudent() async {
    // The class is passed in, so the sheet opens with this one preselected and
    // the teacher does not have to find it in the dropdown.
    final GB_ActionResult? result = await GB_RegisterStudentSheet.show(
      context,
      initialClassId: _classInfo.id,
    );

    if (result == null || !mounted) return;

    final GB_Student? created = result.student;
    if (created == null) {
      // Only reached against a server from before 2026-09-27, when a
      // teacher's registration was a request: no pupil yet, so no id to
      // announce. Registration goes straight in for every role now.
      gShowSnack(context, result.detail);
      unawaited(GB_NotificationStore.loadQuietly());
      return;
    }

    gShowSnack(
      context,
      "${created.name} added to ${_classInfo.name}"
      "${created.rollNumber == null ? "" : " as roll no. ${created.rollNumber}"}",
    );
  }

  /// The principal's "Add teacher" — who takes this class.
  Future<void> _addTeacher() async {
    final GB_ClassInfo? updated = await GB_AddTeacherSheet.show(
      context,
      classInfo: _classInfo,
    );

    // Null means dismissed, and nothing was sent.
    if (updated == null || !mounted) return;

    // This screen holds its own copy of the class, so the header and the next
    // opening of the sheet both need the new one.
    setState(() => _classInfo = updated);

    final List<GB_ClassTeacher> teachers = updated.teachers;
    gShowSnack(
      context,
      teachers.isEmpty
          ? "${updated.name} is now unassigned"
          : "${updated.name} is taught by "
              "${teachers.map((GB_ClassTeacher t) => t.fullName).join(", ")}",
    );
  }

  /// The long-press menu on a student card: Edit or Cancel.
  ///
  /// Delete is deliberately not here — it sits inside the edit form, so
  /// removing a child always goes through their open record first.
  Future<void> _openStudentMenu(GB_Student student) async {
    final bool? edit = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: kPrimaryColor2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kClassPanelRadius),
        ),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 4.0),
              child: Text(
                student.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: kSheetIntroTextSize,
                  fontWeight: FontWeight.w500,
                  color: kHomeTitleTextColor,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: kHomeAccentColor),
              title: const Text("Edit"),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: kHomeSubtitleTextColor),
              title: const Text("Cancel"),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );

    if (edit != true || !mounted) return;

    final GB_ActionResult? result =
        await GB_RegisterStudentSheet.edit(context, student: student);
    if (result == null || !mounted) return;

    // The server words it: "saved", "removed", or — from a teacher's delete —
    // the request now waiting for the principal.
    gShowSnack(context, result.detail);
    if (result.isPending) unawaited(GB_NotificationStore.loadQuietly());
  }

  Future<void> _editClass() async {
    final String previousName = _classInfo.name;
    final Color previousFill = _classInfo.fillColor;
    final GB_ClassInfo? edited = await gEditClass(
      context,
      classInfo: _classInfo,
    );

    // Null means cancelled. The dashboard reads the store directly, so it
    // repaints on its own; only this screen holds a copy that needs replacing.
    if (edited == null || !mounted) return;

    setState(() => _classInfo = edited);

    // The form edits two things, so the confirmation says which one changed —
    // "Class renamed" after a colour change would be a lie, and saying nothing
    // after one leaves the teacher guessing whether Save took. Saving the form
    // untouched is not worth a message at all.
    final bool wasRenamed = edited.name != previousName;
    final bool wasRecoloured = edited.fillColor != previousFill;

    if (wasRenamed) {
      gShowSnack(context, "Class renamed to ${edited.name}");
    } else if (wasRecoloured) {
      gShowSnack(
        context,
        "${edited.name} is now ${GB_ClassPalette.at(_colorSlot).name}",
      );
    }
  }

  /// The palette slot this class is currently painted in.
  int get _colorSlot => GB_ClassPalette.slotForFill(_classInfo.fillColor);

  /// The opaque version of this class's list tint, for the header panel.
  Color get _panelColor => GB_ClassPalette.panelAt(_colorSlot);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      // "Add teacher" is the principal's alone. A teacher has no button for it
      // rather than one that refuses — a control whose only job is to say no
      // is worse than one that was never offered, which is the same reasoning
      // that keeps the Fee tab off their dashboard.
      floatingActionButton: _canRegisterStudents
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_canAssignTeachers) ...[
                  // Two FABs on one route need distinct hero tags, or the
                  // page transition throws.
                  FloatingActionButton.extended(
                    heroTag: "gb_class_add_teacher",
                    onPressed: _addTeacher,
                    backgroundColor: kHomeAccentColor,
                    foregroundColor: kPrimaryColor2,
                    icon: const Icon(Icons.school_outlined),
                    label: const Text("Add teacher"),
                  ),
                  const SizedBox(height: 12.0),
                ],
                FloatingActionButton.extended(
                  heroTag: "gb_class_add_student",
                  onPressed: _registerStudent,
                  backgroundColor: kHomeAccentColor,
                  foregroundColor: kPrimaryColor2,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text("Add student"),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderPanel(),
              const SizedBox(height: 20.0),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: kHomeHorizontalPadding,
                ),
                child: GB_ClassSectionHeader(title: "Features"),
              ),
              const SizedBox(height: 4.0),
              GB_ClassCardRow(
                gap: kFeatureRowGap,
                children: GB_ClassFeature.all
                    .map(
                      (GB_ClassFeature feature) => GB_FeatureCard(
                        feature: feature,
                        onTap: () => gShowSnack(
                          context,
                          "${feature.label} is coming soon",
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16.0),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kHomeHorizontalPadding,
                ),
                child: GB_ClassSectionHeader(
                  title: "Students list",
                  onSeeAll: () =>
                      gShowSnack(context, "The full student list is coming soon"),
                ),
              ),
              const SizedBox(height: 4.0),
              _buildStudentsRow(),
              // Clears the floating buttons, so the last student card is never
              // trapped under them.
              SizedBox(
                height: _canAssignTeachers
                    ? 156.0
                    : _canRegisterStudents
                        ? 88.0
                        : 24.0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The tinted, bottom-rounded panel holding the app bar, the greeting, and
  /// the class's events carousel.
  Widget _buildHeaderPanel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(kClassPanelRadius),
          bottomRight: Radius.circular(kClassPanelRadius),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAppBar(),
          const Padding(
            padding: EdgeInsets.fromLTRB(kHomeHorizontalPadding, 8.0, 16.0, 0.0),
            child: Text(
              "Welcome to your class!",
              style: TextStyle(
                fontSize: kClassWelcomeTextSize,
                height: 24.0 / kClassWelcomeTextSize,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.027,
                color: kHomeTitleTextColor,
              ),
            ),
          ),
          _buildTeacherLine(),
          const SizedBox(height: 16.0),
          _buildEventsCarousel(),
          const SizedBox(height: 12.0),
          Center(
            child: GB_CarouselIndicator(
              count: _events.length,
              activeIndex: _activeEvent,
            ),
          ),
          const SizedBox(height: 20.0),
        ],
      ),
    );
  }

  /// Who teaches this class, under the greeting.
  ///
  /// Shown to everyone, not just the principal: a class with two adults in the
  /// room is a fact about it, and a teacher opening a class they co-teach
  /// should see who else is on it. An unassigned class says so plainly rather
  /// than leaving a blank line that reads as a loading state.
  Widget _buildTeacherLine() {
    final List<GB_ClassTeacher> teachers = _classInfo.teachers;

    final String line;
    if (teachers.isEmpty) {
      line = _canAssignTeachers
          ? "No teacher yet — add one below"
          : "No teacher assigned yet";
    } else {
      // Class teacher first, which is the order the server sends them in.
      line = teachers.map((GB_ClassTeacher t) => t.fullName).join(" · ");
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeHorizontalPadding,
        4.0,
        16.0,
        0.0,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.school_outlined,
            size: kClassDeleteIconSize,
            color: kHomeSubtitleTextColor,
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kEventSubtitleTextSize,
                color: kHomeSubtitleTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Built by hand rather than with [AppBar] so it sits inside the tinted panel
  /// and inherits its colour instead of painting its own background over it.
  Widget _buildAppBar() {
    return SizedBox(
      height: 64.0,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            color: kHomeIconColor,
            iconSize: 24.0,
            tooltip: "Back",
          ),
          Expanded(
            child: Text(
              _classInfo.name,
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
          // A menu rather than a direct action: "edit" is the only entry today,
          // but the three dots are where the class's other actions will land,
          // and a button that silently changes meaning as they arrive is worse
          // than a menu with one item in it.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            iconColor: kHomeIconColor,
            iconSize: 24.0,
            tooltip: "More options",
            color: kPrimaryColor2,
            onSelected: (String value) {
              if (value == "edit") _editClass();
            },
            itemBuilder: (BuildContext context) => const [
              PopupMenuItem<String>(
                value: "edit",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, color: kHomeIconColor),
                  title: Text("Edit class"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The "Students list" strip, read from [GB_StudentStore] so a registration
  /// made from this screen appears in it without a reload.
  ///
  /// Empty until someone registers into this class — a row of stand-in "Name /
  /// Age" cards would look like real pupils and give the teacher nothing to tap
  /// to fix that.
  Widget _buildStudentsRow() {
    return ValueListenableBuilder<List<GB_Student>>(
      valueListenable: GB_StudentStore.students,
      builder: (BuildContext context, List<GB_Student> _, __) {
        final List<GB_Student> students =
            GB_StudentStore.inClass(_classInfo.id);

        if (students.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              kHomeHorizontalPadding,
              12.0,
              kHomeHorizontalPadding,
              0.0,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "No students in this class yet.",
                    style: TextStyle(
                      fontSize: kEventSubtitleTextSize,
                      color: kHomeSubtitleTextColor,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _registerStudent,
                  icon: const Icon(Icons.person_add_alt, size: 18.0),
                  label: const Text("Register"),
                  style: TextButton.styleFrom(
                    foregroundColor: kHomeAccentColor,
                  ),
                ),
              ],
            ),
          );
        }

        return GB_ClassCardRow(
          gap: kStudentRowGap,
          children: students
              .map(
                (GB_Student student) => GB_StudentCard(
                  student: student,
                  onTap: () =>
                      gShowSnack(context, "Student profiles are coming soon"),
                  // A long press rather than a visible button on every card:
                  // editing is occasional, and deleting — reached only from
                  // inside the edit form — is rare and irreversible.
                  onLongPress: () => _openStudentMenu(student),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildEventsCarousel() {
    return CarouselSlider(
      items: _events
          .map(
            (GB_Event event) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kEventCardGutter,
              ),
              child: GB_EventCard(
                event: event,
                onShare: () => gShowSnack(context, "Sharing is coming soon"),
                onTap: () =>
                    gShowSnack(context, "${event.title} is coming soon"),
              ),
            ),
          )
          .toList(),
      options: CarouselOptions(
        height: kEventCardHeight,
        viewportFraction: kEventCardWidthFraction,
        enableInfiniteScroll: _events.length > 1,
        autoPlay: _events.length > 1,
        autoPlayInterval: const Duration(seconds: 5),
        onPageChanged: (index, reason) {
          setState(() => _activeEvent = index);
        },
      ),
    );
  }
}
