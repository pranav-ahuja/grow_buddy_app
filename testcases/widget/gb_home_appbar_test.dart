/// The bar shared by every home screen, and the profile menu that holds the
/// only logout in the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeAppBar.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Settings.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/mock_storage.dart';

void main() {
  setUp(() {
    startTest();
    signInAs(userJson());
  });
  tearDown(endTest);

  Future<void> pumpBar(WidgetTester tester) => pumpScreen(
        tester,
        const Scaffold(appBar: GB_HomeAppBar(), body: SizedBox.shrink()),
      );

  Future<void> openMenu(WidgetTester tester) async {
    await tapAndSettle(tester, find.byTooltip("Profile"));
  }

  testWidgets("appbar_shows_the_title | The bar is titled Grow Buddy",
      (WidgetTester tester) async {
    await pumpBar(tester);

    expect(find.text("Grow Buddy"), findsOneWidget);
  });

  testWidgets("appbar_title_is_overridable | A screen can retitle the bar",
      (WidgetTester tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        appBar: GB_HomeAppBar(title: "Nursery"),
        body: SizedBox.shrink(),
      ),
    );

    expect(find.text("Nursery"), findsOneWidget);
  });

  testWidgets("appbar_has_no_back_button | Nothing takes the hamburger slot",
      (WidgetTester tester) async {
    // automaticallyImplyLeading is off on purpose: the mockup's left-hand menu
    // is covered by the bottom navigation bar instead.
    await pumpBar(tester);

    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets("appbar_menu_is_closed_at_rest | The menu opens only on tap",
      (WidgetTester tester) async {
    await pumpBar(tester);

    expect(find.text("Logout"), findsNothing);
    expect(find.text("Settings"), findsNothing);
  });

  testWidgets("appbar_menu_offers_settings_and_logout | Both items are there",
      (WidgetTester tester) async {
    await pumpBar(tester);

    await openMenu(tester);

    expect(find.text("Settings"), findsOneWidget);
    expect(find.text("Logout"), findsOneWidget);
  });

  testWidgets("appbar_opens_settings | The settings item navigates",
      (WidgetTester tester) async {
    await pumpBar(tester);
    await openMenu(tester);

    await tapAndSettle(tester, find.text("Settings"));

    expect(find.byType(GB_Settings), findsOneWidget);
  });

  testWidgets("appbar_logout_clears_the_session | Logout ends it everywhere",
      (WidgetTester tester) async {
    // The whole logout contract lives in gSignOut: clear the token, sign out
    // of Google, and land on the login page.
    final Map<String, String> storage =
        installStoredSession(token: "stored-jwt");
    signInAs(userJson());
    await pumpBar(tester);
    await openMenu(tester);

    await tapAndSettle(tester, find.text("Logout"));

    expect(gLoginToken, isNull);
    expect(gCurrentUser, isNull);
    expect(storage[kTokenKey], isNull);
  });

  testWidgets("appbar_logout_opens_login | Logout lands on the login form",
      (WidgetTester tester) async {
    // Login rather than onboarding: somebody who just logged out has already
    // seen the intro, and what they want next is the form.
    await pumpBar(tester);
    await openMenu(tester);

    await tapAndSettle(tester, find.text("Logout"));

    expect(find.byType(GB_Login), findsOneWidget);
  });
}
