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
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The teacher's home screen: an events carousel, the class list, a "register
/// new student" action, and the four-tab bottom bar.
///
/// The classes and students come from the server, through [GB_ClassStore] and
/// [GB_StudentStore], so every device signed in to the same account shows the
/// same list. Events are still placeholder data — [_events] is the seam to
/// replace when the backend grows an events endpoint.
class GB_TeacherDashboard extends StatefulWidget {
  const GB_TeacherDashboard({super.key});

  @override
  State<GB_TeacherDashboard> createState() => _GB_TeacherDashboardState();
}

class _GB_TeacherDashboardState extends State<GB_TeacherDashboard>
    with WidgetsBindingObserver {
  /// Which bottom-nav tab is selected. Only Home has a screen so far; the other
  /// three announce themselves and leave the index where it was.
  int _selectedTab = 0;

  /// Which carousel card the indicator should highlight.
  int _activeEvent = 0;

  /// True until the first load has come back, so an account's classes are
  /// not briefly drawn as "no classes" while they are still on their way.
  bool _isFirstLoad = true;

  /// Set when a load failed and there is nothing on screen to fall back on.
  String? _loadError;

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
  /// teacher having to know to pull down: switching back to this app is the
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
    final GB_ClassInfo? created = await GB_AddClassSheet.show(context);

    // Null means the teacher dismissed the sheet. The list repaints itself off
    // the store, so there is nothing to do here but confirm.
    if (created == null || !mounted) return;

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
  /// was — deleting anyway would be the one case where "you can restore it from
  /// the file" is a lie.
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

    try {
      // The server deletes the students with the class; the local prune only
      // brings this device's copy into line.
      await GB_ClassStore.removeClass(classInfo.id);
      GB_StudentStore.removeStudentsInClass(classInfo.id);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      // The class file was written, but the class still exists — saying it was
      // deleted would be the lie. The file is harmless to keep.
      gShowSnack(context, "${classInfo.name} was not deleted — ${error.message}");
      return;
    }

    if (!mounted) return;
    gShowSnack(context, "${classInfo.name} deleted — class file saved");
  }

  /// The caption under a class name: always the real count, never the design's
  /// "no. of students" placeholder. An empty class reads "0 students" rather
  /// than falling back to the wording on [GB_ClassInfo.subtitle].
  String _studentCountLabel(String classId) {
    final int count = GB_StudentStore.countInClass(classId);
    return count == 1 ? "1 student" : "$count students";
  }

  Future<void> _registerStudent() async {
    final GB_Student? created = await GB_RegisterStudentSheet.show(context);

    // Null means the teacher dismissed the sheet. The list repaints itself off
    // the store, so there is nothing to do here but confirm.
    if (created == null || !mounted) return;

    // The design's third screen is "Student added to the class", so the
    // confirmation names the class. Every student has one now; the fallback
    // only covers a class deleted from another device in the meantime.
    final String className = GB_ClassStore.classes.value
            .where((GB_ClassInfo item) => item.id == created.classId)
            .map((GB_ClassInfo item) => item.name)
            .firstOrNull ??
        "their class";

    // The id and roll number are named here because registration is the only
    // place they are announced — everywhere else the teacher has to already
    // know which student card to go and look at.
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

    // The other three screens do not exist yet. Saying so beats moving the
    // highlight to a tab that shows the same body.
    const List<String> labels = ["Home", "Attendance", "Fee", "Message"];
    gShowSnack(context, "${labels[index]} is coming soon");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: const GB_HomeAppBar(),
      body: SafeArea(
        // Pull-to-refresh, for when the teacher knows they just changed
        // something on another device and does not want to wait.
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
                  // The gaps reproduce the design's vertical rhythm on its 360x800
                  // frame: the bar ends at y=88, the dots sit at y=372, the
                  // heading at y=412, and the class list starts at y=464.
                  children: [
                    const SizedBox(height: 16.0),
                    _buildEventsCarousel(),
                    const SizedBox(height: 24.0),
                    GB_CarouselIndicator(
                      count: _events.length,
                      activeIndex: _activeEvent,
                    ),
                    const SizedBox(height: 32.0),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: kHomeHorizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GB_HomeSectionHeader(
                          title: "Your classes at a glance!",
                        ),
                      ),
                    ),
                    const SizedBox(height: 24.0),
                  ],
                ),
              ),
              // A sliver list rather than a Column of tiles: the class list is the
              // only part that grows with the data, so it is what should scroll
              // lazily under the fixed carousel above it.
              //
              // Wrapped in a ValueListenableBuilder so adding a class repaints
              // the list without this screen holding a copy that could drift out
              // of step with the store.
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
                  sliver: ValueListenableBuilder<List<GB_ClassInfo>>(
                    valueListenable: GB_ClassStore.classes,
                    builder: (context, classes, _) {
                      // Nested on the students too, so registering one updates the
                      // count under its class name without this screen recomputing
                      // anything itself.
                      return ValueListenableBuilder<List<GB_Student>>(
                        valueListenable: GB_StudentStore.students,
                        builder: (context, _, __) {
                          return SliverList.builder(
                            // One past the classes for the "Add a class" tile that
                            // closes the list.
                            itemCount: classes.length + 1,
                            itemBuilder: (context, index) {
                              if (index == classes.length) {
                                return GB_AddClassTile(onTap: _addClass);
                              }

                              return GB_ClassTile(
                                classInfo: classes[index],
                                subtitle: _studentCountLabel(classes[index].id),
                                onTap: () => _openClass(classes[index]),
                                onDelete: () => _deleteClass(classes[index]),
                              );
                            },
                          );
                        },
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
                onTap: () => gShowSnack(context, "${event.title} is coming soon"),
              ),
            ),
          )
          .toList(),
      options: CarouselOptions(
        height: kEventCardHeight,
        // Under 1.0 so the neighbouring cards peek in at the edges, the way the
        // mockup shows them.
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
        // Icon names taken from the design's layers, which reference Material's
        // own set — so these are the exact glyphs, not lookalikes.
        //
        // "Attendance" is spelt correctly here even though both the Figma frame
        // and claude_ui/homescreen.jpg read "Attendence". The design has a typo;
        // shipping it would put the misspelling in front of users. Do not
        // "correct" this back to match the mockup.
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.supervisor_account),
            label: "Attendance",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_library),
            label: "Fee",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.question_answer),
            label: "Message",
          ),
        ],
      ),
    );
  }
}
