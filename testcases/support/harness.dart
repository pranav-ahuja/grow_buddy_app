/// Shared setup for widget tests.
///
/// Every widget test goes through here so that each one starts from an
/// identical, isolated world: no leftover session, no classes another test
/// added, and a fake backend rather than a socket.
library;

// The analyzer only treats test/, integration_test/ and test_driver/ as
// test code, and this suite lives in testcases/ by request. These members
// are annotated @visibleForTesting and this IS the test using them.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import 'mock_api.dart';
import 'mock_storage.dart';

/// Wipes every piece of global state the app keeps between screens.
///
/// The app deliberately uses static stores and top-level globals, which means
/// state survives a `testWidgets` boundary. Without this, tests would pass or
/// fail depending on the order they ran in.
void resetAppState() {
  GB_ClassStore.resetForTest();
  GB_StudentStore.resetForTest();
  gLoginToken = null;
  gCurrentUser = null;
}

/// The standard `setUp` for a widget test: clean state, empty secure storage,
/// and a fake backend that has been installed as the app's HTTP client.
FakeApi startTest({Map<String, String>? storageSeed}) {
  resetAppState();
  installMockSecureStorage(storageSeed);
  final FakeApi api = FakeApi();
  api.install();
  return api;
}

/// The standard `tearDown`. Restoring the real client matters: a `MockClient`
/// left installed would silently serve the next test file too.
void endTest() {
  FakeApi.restore();
  resetAppState();
}

/// Signs a user in, for screens that assume an existing session.
void signInAs(Map<String, dynamic> user, {String token = kTestTokenValue}) {
  gLoginToken = token;
  gCurrentUser = GB_User.fromJson(user);
}

const String kTestTokenValue = "test.jwt.token";

/// Records what the app navigated to, for asserting that a screen left.
class RouteSpy extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];
  final List<Route<dynamic>> popped = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

/// Layout overflows seen since the last [startTest].
///
/// A `RenderFlex overflowed` assertion aborts whatever test is running, so a
/// single 6px overflow in a corner of a screen would fail every test that so
/// much as pumps it. They are collected here instead and asserted on in one
/// place — `gb_layout_test.dart` — so the overflow is reported exactly once, as
/// itself, rather than disguised as fifteen unrelated failures.
final List<String> capturedOverflows = <String>[];

/// Routes overflow assertions into [capturedOverflows] and lets everything
/// else fail the test as normal.
void _captureOverflows() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String text = details.exception.toString();
    if (text.contains("overflowed by")) {
      if (!capturedOverflows.contains(text)) capturedOverflows.add(text);
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// Pumps [screen] inside a real `MaterialApp`, so `Navigator`,
/// `ScaffoldMessenger`, and `Theme` all behave as they do in the app.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  RouteSpy? spy,
  Size surfaceSize = const Size(430, 932),
  int frames = 6,
}) async {
  capturedOverflows.clear();
  _captureOverflows();

  // A phone-shaped surface. The default 800x600 test window is landscape, and
  // several of these screens legitimately overflow in it, which would drown
  // real failures in layout noise.
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: screen,
      navigatorObservers: <NavigatorObserver>[if (spy != null) spy],
    ),
  );
  // `frames: 0` stops before any async work resolves, for asserting on what a
  // screen shows while it is still deciding — a loading spinner, say.
  if (frames > 0) await pumpFrames(tester, times: frames);
}

/// Advances a bounded number of frames.
///
/// Deliberately not `pumpAndSettle`: three screens use `carousel_slider` with
/// `autoPlay: true`, so the widget tree is never quiescent and `pumpAndSettle`
/// would spin until it threw. This advances animations far enough for a build
/// and a navigation to complete, without ever requiring them to stop.
Future<void> pumpFrames(
  WidgetTester tester, {
  int times = 6,
  Duration step = const Duration(milliseconds: 120),
}) async {
  for (int i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

/// Taps [finder] and lets the resulting async work and navigation land.
///
/// Scrolls the target into view first. These screens are long
/// `SingleChildScrollView`s, and a tap aimed at a widget below the fold lands
/// on empty space — the test then reads as "nothing happened" rather than as
/// "you tapped outside the window", which is a genuinely confusing hour. A real
/// user scrolls to a button before pressing it, so the test does too.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  try {
    await tester.ensureVisible(finder);
    await tester.pump();
  } on StateError {
    // Not inside a Scrollable — already as visible as it will get.
  }
  await tester.tap(finder);
  await pumpFrames(tester);
}

/// Scrolls the screen up by [by] logical pixels, revealing what is below.
///
/// Drags from a point low on the screen rather than from a widget: the
/// dashboard nests an auto-playing carousel inside its scroll view, and a drag
/// aimed at the scroll view as a whole would land on the carousel and page it
/// sideways instead.
///
/// Needed wherever a list is built lazily — the dashboard's class list is a
/// `SliverList.builder`, so tiles below the fold do not exist in the tree at
/// all until something scrolls them into range.
Future<void> scrollUp(
  WidgetTester tester, {
  double by = 400,
  Offset from = const Offset(215, 700),
}) async {
  await tester.dragFrom(from, Offset(0, -by));
  await pumpFrames(tester);
}

/// Types [text] into [finder], dismissing the keyboard afterwards so the next
/// field is reachable.
Future<void> enterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.enterText(finder, text);
  await tester.pump();
}

/// The text of the SnackBar currently on screen, or null if there is none.
///
/// The app shows the backend's `detail` string verbatim, so this is how a test
/// asserts that a server error actually reached the user.
String? currentSnackBarText(WidgetTester tester) {
  final Finder snack = find.byType(SnackBar);
  if (snack.evaluate().isEmpty) return null;
  final Finder text = find.descendant(of: snack, matching: find.byType(Text));
  if (text.evaluate().isEmpty) return null;
  return tester.widgetList<Text>(text).map((Text t) => t.data ?? "").join(" ");
}

/// Stands in for the photo picker so the register-student form can be tested
/// without a gallery. Pass null to simulate the user cancelling.
void installMockImagePicker(String? returnedPath) {
  const MethodChannel channel = MethodChannel("plugins.flutter.io/image_picker");
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    switch (call.method) {
      case "pickImage":
        return returnedPath;
      case "pickMultiImage":
        return returnedPath == null ? <String>[] : <String>[returnedPath];
      default:
        return null;
    }
  });
}

/// Finds the `TextField` whose floating label reads [label].
///
/// Locating by label rather than by index because the app has no widget keys:
/// an index would silently point at a different box the moment a field is
/// added above it, and the test would keep passing while checking the wrong one.
Finder fieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (Widget widget) {
      if (widget is! TextField) return false;
      final InputDecoration? decoration = widget.decoration;
      if (decoration == null) return false;
      // The app writes labels both ways — `label: Text(...)` in
      // GB_buildTextField, `labelText:` in the bottom sheets — so match either.
      //
      // GB_SheetTextField appends " *" to mark a field required. That is a
      // marker rather than part of the name, so a test asks for "Age" and gets
      // the field whether or not it is currently required.
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

/// The button reading [text].
///
/// Not `find.text`: several screens put the same word in the AppBar title and
/// on the button below it, and tapping an AppBar title does nothing.
Finder buttonWithText(String text) => find.widgetWithText(ElevatedButton, text);

/// Whether the field labelled [label] is currently hiding what is typed in it.
bool isObscured(WidgetTester tester, String label) =>
    tester.widget<TextField>(fieldWithLabel(label)).obscureText;

/// The current contents of the field labelled [label].
String fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(fieldWithLabel(label)).controller?.text ?? "";

/// True when the button reading [text] is disabled.
bool isButtonDisabled(WidgetTester tester, String text) =>
    tester.widget<ElevatedButton>(buttonWithText(text)).onPressed == null;
