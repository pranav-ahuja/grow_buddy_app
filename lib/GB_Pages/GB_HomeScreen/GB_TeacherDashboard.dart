import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeAppBar.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The teacher's home screen: an events carousel, the class list, a "register
/// new student" action, and the four-tab bottom bar.
///
/// Everything shown is placeholder data — the backend has no events or classes
/// endpoint yet. [_events] and [_classes] are the two seams to replace when it
/// does; the widgets below already take their content from those lists.
class GB_TeacherDashboard extends StatefulWidget {
  const GB_TeacherDashboard({super.key});

  @override
  State<GB_TeacherDashboard> createState() => _GB_TeacherDashboardState();
}

class _GB_TeacherDashboardState extends State<GB_TeacherDashboard> {
  /// Which bottom-nav tab is selected. Only Home has a screen so far; the other
  /// three announce themselves and leave the index where it was.
  int _selectedTab = 0;

  /// Which carousel card the indicator should highlight.
  int _activeEvent = 0;

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

  /// The mockup's five classes, each taking the next tint from the palette.
  static final List<GB_ClassInfo> _classes = [
    "Daycare",
    "Playgroup",
    "Pre Nursery",
    "Nursery",
    "KG",
  ].indexed.map((entry) {
    return GB_ClassInfo(
      name: entry.$2,
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: GB_ClassPalette.fillAt(entry.$1),
      borderColor: GB_ClassPalette.borderAt(entry.$1),
    );
  }).toList();

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
        child: CustomScrollView(
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
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: kHomeHorizontalPadding,
              ),
              sliver: SliverList.builder(
                itemCount: _classes.length,
                itemBuilder: (context, index) => GB_ClassTile(
                  classInfo: _classes[index],
                  onTap: () => gShowSnack(
                    context,
                    "${_classes[index].name} is coming soon",
                  ),
                ),
              ),
            ),
            // Clears the FAB so the last class tile is never trapped under it.
            const SliverToBoxAdapter(child: SizedBox(height: 80.0)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            gShowSnack(context, "Register new student is coming soon"),
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
