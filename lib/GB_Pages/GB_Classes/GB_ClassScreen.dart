import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassDialogs.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
// GB_Event and GB_EventCard live with the home screen because that is where
// they first appeared; the class screen shows the same card for the events of
// one class, so it reuses them rather than growing a near-identical copy.
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The screen behind a class tile on the teacher's dashboard.
///
/// Layout follows the Figma frame `360-45584`: a tinted header panel carrying
/// the class's own colour with its events carousel, then the horizontally
/// scrolling "Features" row, then "Students list" with a "See All" link.
///
/// Everything below the class name is placeholder data — there is no classes,
/// events, or students endpoint yet. [_events] and [_students] are the seams to
/// replace when there is.
class GB_ClassScreen extends StatefulWidget {
  const GB_ClassScreen({super.key, required this.classInfo});

  final GB_ClassInfo classInfo;

  @override
  State<GB_ClassScreen> createState() => _GB_ClassScreenState();
}

class _GB_ClassScreenState extends State<GB_ClassScreen> {
  int _activeEvent = 0;

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
    final GB_Student? created = await GB_RegisterStudentSheet.show(
      context,
      initialClassId: _classInfo.id,
    );

    if (created == null || !mounted) return;
    gShowSnack(
      context,
      "${created.name} added to ${_classInfo.name} as ${created.studentId}",
    );
  }

  Future<void> _editClass() async {
    final GB_ClassInfo? renamed = await gEditClassName(
      context,
      classInfo: _classInfo,
    );

    // Null means cancelled. The dashboard reads the store directly, so it
    // repaints on its own; only this screen holds a copy that needs replacing.
    if (renamed == null || !mounted) return;

    setState(() => _classInfo = renamed);
    gShowSnack(context, "Class renamed to ${renamed.name}");
  }

  /// The opaque version of this class's list tint, for the header panel.
  Color get _panelColor =>
      GB_ClassPalette.panelAt(GB_ClassPalette.slotForFill(_classInfo.fillColor));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
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
              const SizedBox(height: 24.0),
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
