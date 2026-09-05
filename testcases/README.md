# testcases/

Automated tests for GrowBuddy, so nobody has to drive the app by hand to find
out whether it still works.

One command runs them and prints a four-column table — **name, description,
result, and a reason when something failed**. The verbose detail goes to
`reports/last_run.json`, never to the console, so a failing run stays a handful
of lines instead of a screenful of stack traces.

```powershell
dart run testcases\run_tests.dart --suite unit,widget     # the default
dart run testcases\run_tests.dart --suite unit            # milliseconds
dart run testcases\run_tests.dart --suite integration --device emulator-5554
dart run testcases\run_tests.dart --suite all
```

```
NAME                                DESCRIPTION                                     RESULT  REASON
login_shows_server_error            The server wording reaches the user             PASS    -
signup_requires_account_type        Skipping the role is refused                    FAIL    Expected: <null> / Actual: <0>
e2e_otp_verifies_and_creates_an_a…  A new number becomes a user                     SKIP    backend not reachable at http://192.168.0.157:8080
----------------------------------------------------------------------------------------------------
311 passed, 1 failed, 0 skipped in 53.3s
Details: testcases/reports/last_run.json
```

Exit code is 0 when everything passed, 1 when anything failed, so it drops
straight into CI or a pre-push hook.

## The three tiers

| Suite | What it runs against | Needs | Speed |
| --- | --- | --- | --- |
| `unit` | Plain Dart — models, stores, the API client | nothing | ~6s |
| `widget` | Real screens, fake backend, fake Keystore | nothing | ~45s |
| `integration` | The real app on a device, against the real backend (in `integration_test/`) | emulator + backend | minutes |

`unit` and `widget` need **no emulator and no server**. They are the ones to run
constantly. `integration` is the one that proves the socket, the JWT, and the
SQLite row actually fit together.

## Layout

```
testcases/
├── run_tests.dart          the entry point and report generator
├── support/                shared test plumbing
│   ├── fixtures.dart       canned backend payloads
│   ├── mock_api.dart       FakeApi — stubs GB_ApiClient.client
│   ├── mock_storage.dart   in-memory flutter_secure_storage
│   └── harness.dart        pumpScreen, finders, state reset
├── unit/                   no widgets
├── widget/                 screens, no device
└── reports/                last_run.json (gitignored)

integration_test/           real device, real backend  <- NOT under testcases/
├── e2e_support.dart
└── *_test.dart
```

**Why the e2e tests live outside this folder.** Flutter only deploys a test to a
device when it sits in a directory named exactly `integration_test/`. Run from
anywhere else and `flutter test -d <device>` quietly executes it on the *host*
instead, where no plugins are registered — `flutter_secure_storage` throws
`MissingPluginException` and every session assertion fails for a reason that has
nothing to do with the app. It is a tooling constraint, not a preference.
`run_tests.dart --suite integration` points there for you.

## Writing a test

Name it `short_name | One-line description`. The runner splits on the `|` to
fill the first two columns, so the report reads as documentation:

```dart
testWidgets("login_shows_server_error | The server wording reaches the user",
    (WidgetTester tester) async {
  api.stubError("/auth/login", status: 401, detail: "Invalid email or password");
  await pumpScreen(tester, const GB_Login());

  await enterText(tester, fieldWithLabel("Email"), "a@b.com");
  await enterText(tester, fieldWithLabel("Password"), "wrong");
  await tapAndSettle(tester, buttonWithText("Login"));

  expect(currentSnackBarText(tester), "Invalid email or password");
});
```

Every widget test starts with `startTest()` and ends with `endTest()`:

```dart
late FakeApi api;
setUp(() => api = startTest());
tearDown(endTest);
```

`startTest()` resets the stores and globals, installs an empty in-memory
Keystore, and points `GB_ApiClient.client` at a fake. `endTest()` puts the real
HTTP client back — without it, one file's fake would silently serve the next.

## Things that will bite you

**`pumpAndSettle` hangs.** Three screens run `carousel_slider` with
`autoPlay: true`, so the widget tree is never quiescent and `pumpAndSettle`
spins until it throws. Use `pumpFrames(tester)` (widget) or `settle(tester)`
(integration) instead — both advance a bounded number of frames.

**Taps below the fold do nothing.** These screens are long
`SingleChildScrollView`s. `tapAndSettle` scrolls the target into view first;
plain `tester.tap` does not, and a tap aimed past the window edge silently lands
on nothing, which reads as "the button is broken".

**Lazy lists are not built until scrolled to.** The dashboard's class list is a
`SliverList.builder`, so the "Add a class" tile at the end does not exist in the
tree until `scrollUp(tester, by: 900)` brings it into range.

**The app has no widget keys.** Zero `Key(...)` and zero `Semantics(...)` in
~6,000 lines of Dart, so every locator keys off visible text via
`fieldWithLabel("Email")` and `buttonWithText("Login")`. That works, but any
copy change breaks a test. Adding a `key:` parameter to the five shared widgets
(`GB_buildTextField`, `GB_ElevatedButtonString`, `GB_ElevatedButtonIcons`,
`GB_SheetTextField`, `GB_PillButton`) would make the whole UI tier robust in one
edit — worth doing when someone has a spare hour.

**Relaunching the app needs the tree torn down first.** `pumpWidget` reuses
element state when the new widget has the same type in the same position, so
pumping the app a second time keeps the old Navigator stack and never re-runs
`GB_SessionGate.initState`. `launchApp` pumps a `SizedBox` in between; without
it a "restart" is no restart at all and the test sits on the screen it was
already on.

**Ask the backend for an OTP only once per number.** Code requests are
rate-limited to one per 30 seconds, so requesting through the UI *and* over HTTP
to read the code back earns a 429 and no code. `pumpForDevCode(tester)` reads it
off the SnackBar the app prints in debug builds instead.

**`DropdownMenu` cannot be tapped by its own type.** It renders as a `Stack`
whose centre sits in the overlay anchor rather than on the field, so
`tap(find.byType(DropdownMenu))` misses on a real device even though it lands on
a larger test surface. Use `chooseFromDropdownMenu(tester, "Teacher")`.

**Layout overflows are swallowed on purpose.** A `RenderFlex overflowed`
assertion aborts whatever test is running, so one 6px overflow in the corner of
a screen would fail every test that merely pumps it. The harness collects them
in `capturedOverflows` instead. **There is a real one:** `GB_Login.dart:229` is a
fixed `height: 100.0` container holding two text buttons that need 106px.

## Running the integration tier

It needs three things, and says which one is missing rather than failing
fifteen assertions in:

1. **A device.** `--device emulator-5554`, or whatever `flutter devices` lists.
   The runner checks first and reports every file as `SKIP` if it is absent.
2. **The backend running.** From `backend/`:
   ```powershell
   .venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8080
   ```
3. **`kApiBaseUrl` pointing at it.** `GB_Constants.dart:197` is a hardcoded
   constant with no `--dart-define` override, currently
   `http://192.168.0.157:8080`. An emulator normally wants `http://10.0.2.2:8080`.
   If the LAN IP changed, it has to be updated **there and** in
   `android/app/src/debug/res/xml/network_security_config.xml`.

Phone login also needs `OTP_DEBUG_RETURN=true` in `backend/.env`, which returns
the code in the API response — there is no SMS provider yet, so it is the only
way that flow can be tested at all.

Each integration test seeds its own account (`tastu+<random>@example.com`), so
the tier is safe to re-run against the persistent `growbuddy.db`.

## What is deliberately not covered

- **Google sign-in.** The button needs real OAuth client IDs and a Google
  account; the backend side is already covered by `backend/tests/test_google_auth.py`.
- **The forgot-password flow's backend.** Those three screens are wired to
  nothing — `gb_password_reset_test.dart` asserts they make *no* HTTP call, so
  the gap stays visible instead of being mistaken for a working feature.
- **Class and student persistence.** Both stores are in memory; there is no
  endpoint yet. Noted in `session_persistence_test.dart`.

## Related

`backend/tests/` holds 34 pytest tests covering the API in-process. They are
separate and still run with:

```powershell
cd backend
.venv\Scripts\python.exe -m pytest -q
```
