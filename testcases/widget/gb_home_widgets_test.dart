/// The presentational pieces the home and class screens are built from.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeWidgets.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

import '../support/harness.dart';

const GB_Event _event = GB_Event(
  title: "Drawing Competition",
  subtitle: "Classes: Nursery & KG",
  imagePath: kEventImage,
);

const GB_ClassInfo _classInfo = GB_ClassInfo(
  id: 3,
  name: "Nursery",
  subtitle: "no. of students",
  imagePath: kClassAvatarImage,
  fillColor: kClassTileGreenFill,
  borderColor: kClassTileGreenBorder,
);

void main() {
  setUp(startTest);
  tearDown(endTest);

  group("GB_EventCard", () {
    testWidgets("event_card_shows_title_and_subtitle | Both lines are drawn",
        (WidgetTester tester) async {
      await pumpScreen(tester, const Scaffold(body: GB_EventCard(event: _event)));

      expect(find.text("Drawing Competition"), findsOneWidget);
      expect(find.text("Classes: Nursery & KG"), findsOneWidget);
    });

    testWidgets("event_card_has_a_share_button | The share action is reachable",
        (WidgetTester tester) async {
      await pumpScreen(tester, const Scaffold(body: GB_EventCard(event: _event)));

      expect(find.byTooltip("Share"), findsOneWidget);
    });

    testWidgets("event_card_share_fires | Tapping share calls back",
        (WidgetTester tester) async {
      int shares = 0;
      await pumpScreen(
        tester,
        Scaffold(body: GB_EventCard(event: _event, onShare: () => shares++)),
      );

      await tapAndSettle(tester, find.byTooltip("Share"));

      expect(shares, 1);
    });

    testWidgets("event_card_tap_fires | Tapping the card calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(body: GB_EventCard(event: _event, onTap: () => taps++)),
      );

      await tapAndSettle(tester, find.text("Drawing Competition"));

      expect(taps, 1);
    });
  });

  group("GB_CarouselIndicator", () {
    testWidgets("indicator_draws_one_dot_per_page | Three events, three dots",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: GB_CarouselIndicator(count: 3, activeIndex: 0)),
      );

      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets("indicator_widens_the_active_dot | The active page is a pill",
        (WidgetTester tester) async {
      // 40x8 for the current page against 8pt circles for the rest, so the
      // width is what says which page you are on.
      await pumpScreen(
        tester,
        const Scaffold(body: GB_CarouselIndicator(count: 3, activeIndex: 1)),
      );

      final Iterable<AnimatedContainer> dots =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final List<double?> widths =
          dots.map((AnimatedContainer d) => d.constraints?.maxWidth).toList();

      expect(widths, [8.0, 40.0, 8.0]);
    });
  });

  group("GB_ClassTile", () {
    testWidgets("class_tile_shows_the_name | The class name is drawn",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: GB_ClassTile(classInfo: _classInfo)),
      );

      expect(find.text("Nursery"), findsOneWidget);
    });

    testWidgets("class_tile_falls_back_to_its_own_subtitle | No override, no problem",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: GB_ClassTile(classInfo: _classInfo)),
      );

      expect(find.text("no. of students"), findsOneWidget);
    });

    testWidgets("class_tile_subtitle_can_be_overridden | The count replaces the caption",
        (WidgetTester tester) async {
      // How the dashboard swaps the design's placeholder for the real count.
      await pumpScreen(
        tester,
        const Scaffold(
          body: GB_ClassTile(classInfo: _classInfo, subtitle: "4 students"),
        ),
      );

      expect(find.text("4 students"), findsOneWidget);
      expect(find.text("no. of students"), findsNothing);
    });

    testWidgets("class_tile_wears_its_own_colour | The tint travels with the class",
        (WidgetTester tester) async {
      // Colour lives on the class rather than being picked by list position,
      // so reordering or filtering the list cannot recolour a class.
      await pumpScreen(
        tester,
        const Scaffold(body: GB_ClassTile(classInfo: _classInfo)),
      );

      final Material material = tester.widget<Material>(
        find.descendant(
          of: find.byType(GB_ClassTile),
          matching: find.byType(Material),
        ),
      );

      expect(material.color, kClassTileGreenFill);
    });

    testWidgets("class_tile_tap_fires | Tapping a class calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(
          body: GB_ClassTile(classInfo: _classInfo, onTap: () => taps++),
        ),
      );

      await tapAndSettle(tester, find.text("Nursery"));

      expect(taps, 1);
    });
  });

  group("GB_AddClassTile", () {
    testWidgets("add_tile_is_labelled | It says what it does",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        Scaffold(body: GB_AddClassTile(onTap: () {})),
      );

      expect(find.text("Add a class"), findsOneWidget);
    });

    testWidgets("add_tile_tap_fires | Tapping it calls back",
        (WidgetTester tester) async {
      int taps = 0;
      await pumpScreen(
        tester,
        Scaffold(body: GB_AddClassTile(onTap: () => taps++)),
      );

      await tapAndSettle(tester, find.text("Add a class"));

      expect(taps, 1);
    });
  });

  group("GB_HomeSectionHeader", () {
    testWidgets("section_header_shows_its_title | The heading is drawn",
        (WidgetTester tester) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: GB_HomeSectionHeader(title: "Your classes at a glance!"),
        ),
      );

      expect(find.text("Your classes at a glance!"), findsOneWidget);
    });
  });
}
