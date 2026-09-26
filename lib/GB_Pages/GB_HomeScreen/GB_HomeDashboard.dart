import 'dart:async';
import 'dart:typed_data';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_AddClassSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassArchive.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassArchiveFile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassDialogs.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassScreen.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_RegisterStudentSheet.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeAppBar.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_NotificationStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// One bottom-nav destination.
class GB_DashboardTab {
  const GB_DashboardTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// What a role may do on the home dashboard.
///
/// The teacher's dashboard and the principal's are the same screen with
/// different powers, so they are one widget configured two ways rather than
/// two copies of ~450 lines that would drift apart the first time either was
/// touched. [GB_TeacherDashboard] and [GB_PrincipalDashboard] are the two
/// configurations, and they are what the router names.
class GB_DashboardPermissions {
  const GB_DashboardPermissions({
    required this.sectionHeader,
    required this.emptyMessage,
    required this.canAddClass,
    required this.canDeleteClass,
    required this.showsClassOwner,
    required this.tabs,
  });

  /// The heading above the class list.
  final String sectionHeader;

  /// Shown when there are no classes. The teacher has an "Add a class" tile to
  /// act on; the principal does not, so they need telling why the list is
  /// empty rather than being left looking at nothing.
  final String emptyMessage;

  /// Whether the list ends with the "Add a class" tile.
  ///
  /// **Both roles have it since 2026-09-20**, and they mean different things
  /// by it. The principal's creates a class outright, under a teacher they
  /// pick or under nobody at all. A teacher's raises a request the principal
  /// has to grant, and nothing appears on any dashboard until they do.
  ///
  /// The distinction is not drawn here on purpose. The server decides it from
  /// who is asking and says which happened, and a screen that also decided it
  /// would be a second copy of the rule to keep in step.
  final bool canAddClass;

  /// Whether tiles carry the bin icon.
  ///
  /// Deleting a class writes its `.xlsx` archive first and then removes every
  /// student in it. The principal's takes effect; a teacher's is a request,
  /// and the archive is written either way — so an approval that comes
  /// tomorrow finds the file already saved.
  final bool canDeleteClass;

  /// Whether the caption names the teacher who owns the class. Only useful
  /// where the list spans more than one teacher.
  final bool showsClassOwner;

  final List<GB_DashboardTab> tabs;

  /// The teacher: the classes they take — the ones they own and the ones the
  /// principal added them to as a co-teacher.
  ///
  /// They may still start an add or a delete; both become requests. Saying so
  /// is the add sheet's and the confirmation's job, not this list's.
  ///
  /// **No Fee tab.** Fee status belongs to the principal, so it is absent from
  /// the teacher's bar rather than present and refusing — a tab that exists
  /// only to say no is worse than one that was never offered.
  static const GB_DashboardPermissions teacher = GB_DashboardPermissions(
    sectionHeader: "Your classes at a glance!",
    emptyMessage: "No classes yet. Add your first one below.",
    canAddClass: true,
    canDeleteClass: true,
    showsClassOwner: false,
    tabs: [
      GB_DashboardTab(label: "Home", icon: Icons.home),
      GB_DashboardTab(label: "Attendance", icon: Icons.supervisor_account),
      GB_DashboardTab(label: "Message", icon: Icons.question_answer),
    ],
  );

  /// The principal: every class in the school, and the admin's powers over
  /// them — create, delete, and hand to a teacher — plus the Fee tab.
  static const GB_DashboardPermissions principal = GB_DashboardPermissions(
    sectionHeader: "Every class in the school",
    emptyMessage: "No classes yet. Add the school's first one below.",
    canAddClass: true,
    canDeleteClass: true,
    showsClassOwner: true,
    tabs: [
      GB_DashboardTab(label: "Home", icon: Icons.home),
      GB_DashboardTab(label: "Attendance", icon: Icons.supervisor_account),
      GB_DashboardTab(label: "Fee", icon: Icons.local_library),
      GB_DashboardTab(label: "Message", icon: Icons.question_answer),
    ],
  );
}

/// The home screen behind both the teacher's and the principal's dashboard: an
/// events carousel, the class list, a "register new student" action, and the
/// bottom bar.
///
/// The classes and students come from the server through [GB_ClassStore] and
/// [GB_StudentStore], **scoped by the caller's role on the server side** — the
/// same `GET /classes` returns one teacher's classes to a teacher and every
/// class in the school to a principal. This screen does no filtering of its
/// own, so it cannot disagree with who the server thinks you are.
///
/// Events are still placeholder data — [_events] is the seam to replace when
/// the backend grows an events endpoint.
class GB_HomeDashboard extends StatefulWidget {
  const GB_HomeDashboard({super.key, required this.permissions});

  final GB_DashboardPermissions permissions;

  @override
  State<GB_HomeDashboard> createState() => _GB_HomeDashboardState();
}

class _GB_HomeDashboardState extends State<GB_HomeDashboard>
    with WidgetsBindingObserver {
  /// Which bottom-nav tab is selected. Only Home has a screen so far; the
  /// others announce themselves and leave the index where it was.
  int _selectedTab = 0;

  /// Which carousel card the indicator should highlight.
  int _activeEvent = 0;

  /// True until the first load has come back, so an account's classes are
  /// not briefly drawn as "no classes" while they are still on their way.
  bool _isFirstLoad = true;

  /// Set when a load failed and there is nothing on screen to fall back on.
  String? _loadError;

  GB_DashboardPermissions get _can => widget.permissions;

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
  /// This is what makes a class added on another device turn up without the
  /// user having to know to pull down: switching back to this app is the
  /// moment they are about to look at the list.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Fetches the classes and students from the server.
  ///
  /// Both together, since the tiles need both — a class list without its
  /// students would show every class as "0 students" for a moment.
  Future<void> _refresh() async {
    // The notifications go up with them, so the bell's badge is right by the
    // time the dashboard is drawn. [loadQuietly] because a bell that could
    // not refresh must not be what stops a teacher seeing their classes.
    unawaited(GB_NotificationStore.loadQuietly());

    try {
      await Future.wait([GB_ClassStore.load(), GB_StudentStore.load()]);
      if (!mounted) return;
      setState(() {
        _isFirstLoad = false;
        _loadError = null;
      });
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isFirstLoad = false;
        // With classes already on screen, a failed refresh is a passing
        // remark; with nothing on screen, it is the whole story.
        if (GB_ClassStore.classes.value.isEmpty) _loadError = error.message;
      });
      gShowSnack(context, error.message);
    }
  }

  static const List<GB_Event> _events = [
    GB_Event(
      title: "Drawing Competition",
      subtitle: "Classes: Nursery & KG",
      imagePath: kEventImage,
    ),
    GB_Event(
      title: "Sports Day",
      subtitle: "Classes: All",
      imagePath: kEventImage,
    ),
    GB_Event(
      title: "Annual Function",
      subtitle: "Classes: Pre Nursery & Nursery",
      imagePath: kEventImage,
    ),
  ];

  void _openClass(GB_ClassInfo classInfo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GB_ClassScreen(classInfo: classInfo),
      ),
    );
  }

  Future<void> _addClass() async {
    final GB_ActionResult? result = await GB_AddClassSheet.show(context);

    // Null means the sheet was dismissed. The list repaints itself off the
    // store, so there is nothing to do here but confirm.
    if (result == null || !mounted) return;

    final GB_ClassInfo? created = result.classInfo;
    if (created == null) {
      // A teacher's: nothing was created, a request is waiting. The server's
      // own sentence says so — the app would otherwise have to know the
      // approval rule in order to word this, and be wrong the day it changes.
      gShowSnack(context, result.detail);
      // The badge moves the moment their request lands in the principal's
      // queue, and it is the only sign on this screen that anything happened.
      unawaited(GB_NotificationStore.loadQuietly());
      return;
    }

    // A class restored from a file arrives with its students already in the
    // store, so the count is what says whether this was a fresh class or a
    // recovery.
    final int restored = GB_StudentStore.countInClass(created.id);
    gShowSnack(
      context,
      restored == 0
          ? "${created.name} added"
          : "${created.name} restored with $restored "
              "${restored == 1 ? "student" : "students"}",
    );
  }

  /// Deletes a class, but only after its archive has actually been written.
  ///
  /// The order matters and is the whole safety net: confirm, save, then delete.
  /// If the teacher backs out of the save dialog the class stays exactly as it
  /// was — deleting anyway would be the one case where "you can restore it
  /// from the file" is a lie.
  Future<void> _deleteClass(GB_ClassInfo classInfo) async {
    final List<GB_Student> students = GB_StudentStore.inClass(classInfo.id);

    final bool confirmed = await gConfirmDeleteClass(
      context,
      classInfo: classInfo,
      studentCount: students.length,
    );
    if (!confirmed || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = GB_ClassArchive.encode(
        className: classInfo.name,
        students: students,
      );
    } on GB_ClassArchiveException catch (error) {
      if (!mounted) return;
      gShowSnack(context, error.message);
      return;
    }

    final String? savedTo = await GB_ClassArchiveFile.save(
      fileName: GB_ClassArchive.fileNameFor(classInfo.name),
      bytes: bytes,
    );
    if (!mounted) return;

    if (savedTo == null) {
      gShowSnack(context, "${classInfo.name} was not deleted — no file saved");
      return;
    }

    final GB_ActionResult result;
    try {
      // The server deletes the students with the class; the local prune only
      // brings this device's copy into line. A teacher's delete deletes
      // nothing yet, and [GB_ClassStore.removeClass] knows not to prune then.
      result = await GB_ClassStore.removeClass(classInfo.id);
      if (result.isDone) {
        GB_StudentStore.removeStudentsInClass(classInfo.id);
      }
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      // The class file was written, but the class still exists — saying it was
      // deleted would be the lie. The file is harmless to keep.
      gShowSnack(
        context,
        "${classInfo.name} was not deleted — ${error.message}",
      );
      return;
    }

    if (!mounted) return;
    if (result.isDone) {
      gShowSnack(context, "${classInfo.name} deleted — class file saved");
      return;
    }

    // Waiting on the principal. The archive was still written first, and
    // saying so matters: the teacher has a file on their device for a class
    // that is still on their dashboard, and without this that reads as a
    // delete that half happened.
    gShowSnack(context, "${result.detail} The class file has been saved.");
    unawaited(GB_NotificationStore.loadQuietly());
  }

  /// The caption under a class name: always the real count, never the design's
  /// "no. of students" placeholder. An empty class reads "0 students" rather
  /// than falling back to the wording on [GB_ClassInfo.subtitle].
  ///
  /// On the principal's list the owning teacher is named alongside it, because
  /// that list spans every teacher and two of them may have a class of the
  /// same name.
  String _classSubtitle(GB_ClassInfo classInfo) {
    final int count = GB_StudentStore.countInClass(classInfo.id);
    final String students = count == 1 ? "1 student" : "$count students";

    final String? owner = classInfo.teacherName;
    if (!_can.showsClassOwner || owner == null || owner.isEmpty) {
      return students;
    }
    return "$owner · $students";
  }

  Future<void> _registerStudent() async {
    final GB_ActionResult? result = await GB_RegisterStudentSheet.show(context);

    // Null means the sheet was dismissed.
    if (result == null || !mounted) return;

    final GB_Student? created = result.student;
    if (created == null) {
      // A teacher's registration is a request; no pupil exists yet, so there
      // is no id or roll number to announce.
      gShowSnack(context, result.detail);
      unawaited(GB_NotificationStore.loadQuietly());
      return;
    }

    // The design's third screen is "Student added to the class", so the
    // confirmation names the class. Every student has one now; the fallback
    // only covers a class deleted from another device in the meantime.
    final String className = GB_ClassStore.classes.value
            .where((GB_ClassInfo item) => item.id == created.classId)
            .map((GB_ClassInfo item) => item.name)
            .firstOrNull ??
        "their class";

    // The id and roll number are named here because registration is the only
    // place they are announced — everywhere else the user has to already know
    // which student card to go and look at.
    gShowSnack(
      context,
      "${created.name} added to $className as ${created.studentId}"
      "${created.rollNumber == null ? "" : ", roll no. ${created.rollNumber}"}",
    );
  }

  void _onTabTapped(int index) {
    if (index == 0) {
      setState(() => _selectedTab = index);
      return;
    }

    // The other screens do not exist yet. Saying so beats moving the highlight
    // to a tab that shows the same body.
    gShowSnack(context, "${_can.tabs[index].label} is coming soon");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: const GB_HomeAppBar(),
      body: SafeArea(
        // Pull-to-refresh, for when the user knows they just changed something
        // on another device and does not want to wait.
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: kHomeAccentColor,
          child: CustomScrollView(
            // Always scrollable, or a list too short to scroll could never be
            // pulled down to refresh.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  // The gaps reproduce the design's vertical rhythm on its
                  // 360x800 frame: the bar ends at y=88, the dots sit at
                  // y=372, the heading at y=412, the class list at y=464.
                  children: [
                    const SizedBox(height: 16.0),
                    _buildEventsCarousel(),
                    const SizedBox(height: 24.0),
                    GB_CarouselIndicator(
                      count: _events.length,
                      activeIndex: _activeEvent,
                    ),
                    const SizedBox(height: 32.0),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeHorizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GB_HomeSectionHeader(
                          title: _can.sectionHeader,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24.0),
                  ],
                ),
              ),
              // A sliver list rather than a Column of tiles: the class list is
              // the only part that grows with the data, so it is what should
              // scroll lazily under the fixed carousel above it.
              if (_isFirstLoad)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: CircularProgressIndicator(color: kHomeAccentColor),
                    ),
                  ),
                )
              else if (_loadError != null)
                SliverToBoxAdapter(child: _buildLoadError(_loadError!))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kHomeHorizontalPadding,
                  ),
                  // Wrapped in a ValueListenableBuilder so adding a class
                  // repaints the list without this screen holding a copy that
                  // could drift out of step with the store.
                  sliver: ValueListenableBuilder<List<GB_ClassInfo>>(
                    valueListenable: GB_ClassStore.classes,
                    builder: (context, classes, _) {
                      // Nested on the students too, so registering one updates
                      // the count under its class name without this screen
                      // recomputing anything itself.
                      return ValueListenableBuilder<List<GB_Student>>(
                        valueListenable: GB_StudentStore.students,
                        builder: (context, _, __) => _buildClassList(classes),
                      );
                    },
                  ),
                ),
              // Clears the FAB so the last class tile is never trapped under it.
              const SliverToBoxAdapter(child: SizedBox(height: 80.0)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _registerStudent,
        backgroundColor: kHomeAccentColor,
        foregroundColor: kPrimaryColor2,
        // The design rings the button in white so it stays separated from the
        // tinted class card it overlaps.
        shape: const CircleBorder(
          side: BorderSide(color: kPrimaryColor2),
        ),
        tooltip: "Register new student",
        child: const Icon(Icons.group_add),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildClassList(List<GB_ClassInfo> classes) {
    // Nothing to show and nothing to add: say why, rather than leaving the
    // reader looking at an empty screen and wondering if it failed.
    if (classes.isEmpty && !_can.canAddClass) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            _can.emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: kEventSubtitleTextSize,
              height: 1.4,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ),
      );
    }

    return SliverList.builder(
      // One past the classes for the "Add a class" tile that closes the list,
      // where the role has one.
      itemCount: classes.length + (_can.canAddClass ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == classes.length) {
          return GB_AddClassTile(onTap: _addClass);
        }

        final GB_ClassInfo classInfo = classes[index];
        return GB_ClassTile(
          classInfo: classInfo,
          subtitle: _classSubtitle(classInfo),
          onTap: () => _openClass(classInfo),
          // Null draws no bin icon at all, which is what a role that may not
          // delete should see — not a button that refuses.
          onDelete:
              _can.canDeleteClass ? () => _deleteClass(classInfo) : null,
        );
      },
    );
  }

  /// Stands in for the class list when the first load failed, with a way to
  /// try again that does not depend on knowing pull-to-refresh exists.
  Widget _buildLoadError(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kHomeHorizontalPadding,
        vertical: 16.0,
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: kEventSubtitleTextSize,
              height: 1.4,
              color: kHomeSubtitleTextColor,
            ),
          ),
          const SizedBox(height: 12.0),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _isFirstLoad = true;
                _loadError = null;
              });
              _refresh();
            },
            style: OutlinedButton.styleFrom(foregroundColor: kHomeAccentColor),
            child: const Text("Try again"),
          ),
        ],
      ),
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
        // Under 1.0 so the neighbouring cards peek in at the edges, the way
        // the mockup shows them.
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

  /// The design draws a hairline along the top of the bar instead of the
  /// elevation shadow Material would add, so the bar is wrapped rather than
  /// returned bare.
  ///
  /// The destinations come from the role: a teacher has no Fee tab, because
  /// fee status is the principal's.
  ///
  /// Icon names are taken from the design's layers, which reference Material's
  /// own set — so these are the exact glyphs, not lookalikes.
  ///
  /// "Attendance" is spelt correctly even though both the Figma frame and
  /// claude_ui/homescreen.jpg read "Attendence". The design has a typo;
  /// shipping it would put the misspelling in front of users. Do not
  /// "correct" this back to match the mockup.
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: kPrimaryColor2,
        border: Border(top: BorderSide(color: kHomeNavBorderColor)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: kPrimaryColor2,
        elevation: 0.0,
        selectedItemColor: kHomeAccentColor,
        unselectedItemColor: kHomeTitleTextColor,
        selectedFontSize: kHomeNavSelectedTextSize,
        unselectedFontSize: kHomeNavUnselectedTextSize,
        items: [
          for (final GB_DashboardTab tab in _can.tabs)
            BottomNavigationBarItem(
              icon: Icon(tab.icon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
