/// Shared plumbing for the end-to-end tests.
///
/// These run the **real app** on a device against the **real backend** — no
/// mocks anywhere. That is the point: they are the only tests that prove the
/// pieces the widget suite stubs out (the socket, the JWT, the SQLite row)
/// actually fit together.
///
/// Requires:
///   * a device or emulator (`--device emulator-5554`)
///   * the backend running and reachable at [kApiBaseUrl]
///   * `OTP_DEBUG_RETURN=true` for the phone-login test
library;

// The analyzer only treats test/, integration_test/ and test_driver/ as test
// code for some checks; resetForTest is annotated @visibleForTesting and this
// is the test using it.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Startup/GB_SessionGate.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:http/http.dart' as http;

/// A fresh identifier per run, so the suite can be run repeatedly against the
/// persistent `growbuddy.db` without tripping the duplicate-account rule.
String uniqueEmail() {
  final String tag = _randomTag();
  return "tastu+$tag@example.com";
}

/// A phone number in the +91 9xxxxxxxxx range that no earlier run has used.
String uniquePhone() {
  final Random random = Random.secure();
  final String digits =
      List<int>.generate(9, (_) => random.nextInt(10)).join();
  return "+919$digits";
}

String _randomTag() {
  final Random random = Random.secure();
  const String alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  return List<String>.generate(
    8,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

/// Whether the backend is up, so a test can skip with a clear reason instead of
/// failing fifteen assertions into a flow.
Future<bool> backendIsReachable() async {
  try {
    final http.Response response = await http
        .get(Uri.parse("$kApiBaseUrl/health"))
        .timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  } on Object {
    return false;
  }
}

/// The message shown when the backend cannot be reached.
///
/// Names the URL the app is actually compiled against, because the usual cause
/// is that `kApiBaseUrl` points at a LAN address this machine no longer has —
/// it is a hardcoded constant with no `--dart-define` override.
String get backendUnreachableReason =>
    "backend not reachable at $kApiBaseUrl - start it "
    "(backend/README.md) and check kApiBaseUrl in GB_Constants.dart";

/// Reads the debug OTP straight from the backend.
///
/// The app also surfaces it in a SnackBar in debug builds, but reading it here
/// is steadier than racing a four-second snackbar, and it is the same code
/// either way.
Future<String?> requestOtpDirectly(String phone) async {
  final http.Response response = await http.post(
    Uri.parse(kOtpRequestUrl),
    headers: const {"Content-Type": "application/json"},
    body: jsonEncode({"phone": phone}),
  );
  if (response.statusCode != 200) return null;
  return (jsonDecode(response.body) as Map<String, dynamic>)["debug_otp"]
      as String?;
}

/// Clears every trace of a previous run from the device.
///
/// The session lives in the Keystore and survives a reinstall on some devices,
/// so a test that assumed a signed-out start would otherwise open straight on
/// the dashboard.
Future<void> resetDevice() async {
  await GB_SessionStore.clear();
  gLoginToken = null;
  gCurrentUser = null;

  // The class and student stores are static, and every test in a file shares
  // one isolate — so without this, a pupil registered by an earlier test is
  // still in the roster the next one expects to find empty.
  GB_ClassStore.resetForTest();
  GB_StudentStore.resetForTest();
}

/// Starts the app at [GB_SessionGate] — the same entry the splash screen leads
/// to, minus the splash animation, which only adds two seconds per test.
Future<void> launchApp(WidgetTester tester) async {
  // Tear the previous tree down first.
  //
  // `pumpWidget` reuses element state when the new widget has the same type in
  // the same position, so relaunching without this keeps the old Navigator
  // stack and never re-runs GB_SessionGate.initState — the "restart" would be
  // no restart at all, and a test would sit on the screen it was already on
  // while believing it had gone back to the start.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GB_SessionGate(),
    ),
  );
  await settle(tester);
}

/// Advances a bounded number of frames.
///
/// Deliberately not `pumpAndSettle`: three screens run an auto-playing
/// `carousel_slider`, so the tree is never quiescent and `pumpAndSettle` would
/// spin until it threw. Longer here than in the widget suite because these
/// frames are waiting on a real server over a real socket.
Future<void> settle(
  WidgetTester tester, {
  int times = 12,
  Duration step = const Duration(milliseconds: 250),
}) async {
  for (int i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

/// Taps [finder] after scrolling it into view, then waits for the result.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  try {
    await tester.ensureVisible(finder);
    await tester.pump();
  } on StateError {
    // Not inside a Scrollable — already as visible as it will get.
  }
  await tester.tap(finder);
  await settle(tester);
}

/// Types [text] into [finder].
Future<void> enterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Finds the `TextField` whose label reads [label]. Mirrors the widget suite's
/// finder, since the app still has no widget keys to target.
Finder fieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (Widget widget) {
      if (widget is! TextField) return false;
      final InputDecoration? decoration = widget.decoration;
      if (decoration == null) return false;
      if (decoration.labelText == label ||
          decoration.labelText == "$label *") {
        return true;
      }
      final Widget? decorationLabel = decoration.label;
      return decorationLabel is Text && decorationLabel.data == label;
    },
    description: 'TextField labelled "$label"',
  );
}

Finder buttonWithText(String text) => find.widgetWithText(ElevatedButton, text);

/// Opens a Material 3 [DropdownMenu] and picks the entry reading [option].
///
/// Taps the `TextField` inside the menu rather than the menu itself: a
/// `DropdownMenu` renders as a `Stack` whose centre sits in the overlay anchor,
/// not on the field, so `tap(find.byType(DropdownMenu))` derives an offset that
/// misses on a real device even though it happens to land on a larger test
/// surface.
Future<void> chooseFromDropdownMenu(
  WidgetTester tester,
  String option,
) async {
  final Finder field = find.descendant(
    of: find.byType(DropdownMenu<String>),
    matching: find.byType(TextField),
  );

  await tapAndSettle(tester, field.first);
  // The open menu adds a second copy of the label, so take the last.
  await tapAndSettle(tester, find.text(option).last);
}

/// Picks [className] from the register-student form's class dropdown.
///
/// A `DropdownButtonFormField`, unlike the sign-up screen's `DropdownMenu`, so
/// it opens on its own hit box and only the entry needs disambiguating.
Future<void> chooseClass(WidgetTester tester, String className) async {
  await tapAndSettle(tester, find.byType(DropdownButtonFormField<int?>));
  await tapAndSettle(tester, find.text(className).last);
}

/// Scrolls up from a point low on the screen, for lazily-built lists.
Future<void> scrollUp(WidgetTester tester, {double by = 400}) async {
  await tester.dragFrom(const Offset(215, 700), Offset(0, -by));
  await settle(tester, times: 4);
}

/// True when the device the tests are running on is not the host.
bool get isOnDevice => Platform.isAndroid || Platform.isIOS;

/// The dev OTP out of the SnackBar the app shows in debug builds.
///
/// Reading it off the screen rather than asking the backend again matters: code
/// requests are rate-limited to one per 30 seconds per number, so a test that
/// requests through the UI *and* over HTTP gets a 429 for its second call and
/// no code at all.
String? devCodeFromSnackBar(WidgetTester tester) {
  final Finder snack = find.byType(SnackBar);
  if (snack.evaluate().isEmpty) return null;

  final Iterable<Text> texts = tester.widgetList<Text>(
    find.descendant(of: snack, matching: find.byType(Text)),
  );
  for (final Text text in texts) {
    final Match? match =
        RegExp(r"dev code:\s*(\d{4,8})").firstMatch(text.data ?? "");
    if (match != null) return match.group(1);
  }
  return null;
}

/// Pumps in small steps, watching for the dev-code SnackBar before it expires.
///
/// The SnackBar lives four seconds, and [settle] advances three in one go, so
/// a plain settle can step straight over it.
Future<String?> pumpForDevCode(WidgetTester tester) async {
  String? code;
  for (int i = 0; i < 18; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    code ??= devCodeFromSnackBar(tester);
  }
  return code;
}
