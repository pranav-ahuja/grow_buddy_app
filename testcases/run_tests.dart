/// The entry point for the whole suite.
///
/// Wraps `flutter test --machine`, whose newline-delimited JSON is turned into
/// a four-column table: name, description, result, and — only when something
/// broke — the reason. Full stack traces go to reports/last_run.json and never
/// to the console, so a failing run stays a handful of lines rather than a
/// screenful of traceback.
///
///   dart run testcases/run_tests.dart --suite unit
///   dart run testcases/run_tests.dart --suite unit,widget
///   dart run testcases/run_tests.dart --suite all --device emulator-5554
library;

import 'dart:convert';
import 'dart:io';

const String _reportDir = "testcases/reports";

const Map<String, String> _suitePaths = {
  "unit": "testcases/unit",
  "widget": "testcases/widget",
  // Not under testcases/ like the other two: Flutter only deploys a test to a
  // device when it lives in a directory named integration_test/. Run from
  // anywhere else and it executes on the host instead, where the plugins are
  // not registered and flutter_secure_storage throws MissingPluginException.
  "integration": "integration_test",
};

/// One row of the report.
class TestRow {
  final String name;
  final String description;
  String result = "PASS";
  String reason = "";
  String detail = "";
  String suite = "";

  TestRow(this.name, this.description);

  Map<String, dynamic> toJson() => {
        "name": name,
        "description": description,
        "result": result,
        "reason": reason,
        "detail": detail,
        "suite": suite,
      };
}

Future<int> main(List<String> args) async {
  final _Options options = _Options.parse(args);

  if (options.suites.isEmpty) {
    stderr.writeln("Unknown suite. Use: unit, widget, integration, or all.");
    exit(2);
  }

  final List<TestRow> rows = <TestRow>[];
  final Stopwatch clock = Stopwatch()..start();
  bool anyFailed = false;

  for (final String suite in options.suites) {
    final Directory dir = Directory(_suitePaths[suite]!);
    if (!dir.existsSync() || _dartFilesIn(dir).isEmpty) {
      stdout.writeln("(no tests in $suite yet - skipping)");
      continue;
    }

    // Integration tests need a device. Reporting that once, up front, beats
    // half a dozen identical connection failures.
    if (suite == "integration") {
      final String? blocker = await _integrationBlocker(options.device);
      if (blocker != null) {
        for (final File file in _dartFilesIn(dir)) {
          rows.add(TestRow(_fileLabel(file), "Whole file skipped before it ran")
            ..result = "SKIP"
            ..reason = blocker
            ..suite = suite);
        }
        continue;
      }
    }

    final _SuiteOutcome outcome = await _runSuite(
      suite: suite,
      path: dir.path,
      device: options.device,
      verbose: options.verbose,
    );
    rows.addAll(outcome.rows);
    anyFailed = anyFailed || outcome.failed;
  }

  clock.stop();
  _printTable(rows, clock.elapsed);
  _writeReport(rows, clock.elapsed);

  exit(anyFailed ? 1 : 0);
}

class _Options {
  final List<String> suites;
  final String device;
  final bool verbose;

  _Options(this.suites, this.device, this.verbose);

  static _Options parse(List<String> args) {
    String raw = "unit,widget";
    String device = "emulator-5554";
    bool verbose = false;

    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case "--suite":
          if (i + 1 < args.length) raw = args[++i];
        case "--device":
          if (i + 1 < args.length) device = args[++i];
        case "--verbose":
          verbose = true;
      }
    }

    final List<String> suites = raw == "all"
        ? _suitePaths.keys.toList()
        : raw
            .split(",")
            .map((String s) => s.trim())
            .where(_suitePaths.containsKey)
            .toList();

    return _Options(suites, device, verbose);
  }
}

class _SuiteOutcome {
  final List<TestRow> rows;
  final bool failed;
  _SuiteOutcome(this.rows, this.failed);
}

List<File> _dartFilesIn(Directory dir) {
  if (!dir.existsSync()) return <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith("_test.dart"))
      .toList();
}

String _fileLabel(File file) =>
    file.uri.pathSegments.last.replaceAll("_test.dart", "");

/// Runs one suite and turns the `--machine` event stream into rows.
Future<_SuiteOutcome> _runSuite({
  required String suite,
  required String path,
  required String device,
  required bool verbose,
}) async {
  final List<String> command = <String>[
    "test",
    path,
    "--machine",
    if (suite == "integration") ...<String>["-d", device],
  ];

  final Process process = await Process.start(
    Platform.isWindows ? "flutter.bat" : "flutter",
    command,
    runInShell: true,
  );

  final Map<int, TestRow> byId = <int, TestRow>{};
  final Map<TestRow, String> prints = <TestRow, String>{};
  final List<TestRow> ordered = <TestRow>[];
  bool failed = false;

  final Future<void> stderrDrain =
      process.stderr.transform(utf8.decoder).forEach((String chunk) {
    if (verbose) stderr.write(chunk);
  });

  await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((String line) {
    if (!line.startsWith("{")) return;

    final Map<String, dynamic> event;
    try {
      event = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      return;
    }

    switch (event["type"]) {
      case "testStart":
        final Map<String, dynamic> test = event["test"] as Map<String, dynamic>;
        final int id = test["id"] as int;
        final String rawName = (test["name"] as String? ?? "").trim();
        // The runner emits one hidden "loading <file>" pseudo-test per file.
        if (rawName.startsWith("loading ")) return;

        final TestRow row = _rowFromName(rawName)..suite = suite;
        byId[id] = row;
        ordered.add(row);

      case "print":
        // A widget-test failure reports only "Test failed. See exception logs
        // above." in its error event; the actual expectation lives in the
        // console dump that arrives as a print. Keep the last one per test so
        // the REASON column can say something useful.
        final TestRow? row = byId[event["testID"] as int?];
        if (row == null) return;
        final String message = (event["message"] as String? ?? "").trim();
        // Only the exception dumps. The framework also prints advisory notes
        // (the HttpClient warning, for one) that would otherwise be mistaken
        // for the reason a test failed.
        if (message.contains("EXCEPTION CAUGHT") ||
            message.contains(" was thrown")) {
          prints[row] = message;
        }

      case "error":
        final TestRow? row = byId[event["testID"] as int?];
        if (row == null) return;
        final String message = (event["error"] as String? ?? "").trim();
        final String stack = (event["stackTrace"] as String? ?? "").trim();
        if (row.reason.isEmpty) row.reason = _squash(message);
        row.detail = stack.isEmpty ? message : "$message\n$stack";

      case "testDone":
        final TestRow? row = byId[event["testID"] as int?];
        if (row == null) return;
        if (event["hidden"] == true) {
          ordered.remove(row);
          return;
        }
        if (event["skipped"] == true) {
          row.result = "SKIP";
          if (row.reason.isEmpty) row.reason = "marked skip";
        } else if (event["result"] != "success") {
          row.result = "FAIL";
          failed = true;
          final String dump = prints[row] ?? "";
          if (row.reason.isEmpty || _isUseless(row.reason)) {
            final String fromDump = _reasonFromDump(dump);
            if (fromDump.isNotEmpty) row.reason = fromDump;
          }
          if (row.reason.isEmpty) row.reason = "failed without a message";
          if (dump.isNotEmpty) {
            row.detail = row.detail.isEmpty ? dump : "${row.detail}\n\n$dump";
          }
        }
    }
  });

  await stderrDrain;
  final int code = await process.exitCode;

  // A compile error produces no test events at all, and quietly reporting
  // "0 tests" would read as success.
  if (ordered.isEmpty && code != 0) {
    failed = true;
    ordered.add(TestRow(suite, "Suite did not run")
      ..result = "FAIL"
      ..reason = "flutter test exited $code (rerun with --verbose)"
      ..suite = suite);
  }

  return _SuiteOutcome(ordered, failed);
}

/// Splits a test name of the form `short_name | One-line description` into its
/// two columns.
///
/// The runner prepends group names, so the short name is the last
/// whitespace-separated token before the pipe.
TestRow _rowFromName(String rawName) {
  final int pipe = rawName.indexOf("|");
  if (pipe == -1) {
    final List<String> words = rawName.split(RegExp(r"\s+"));
    return TestRow(words.isEmpty ? rawName : words.last, "");
  }

  final String left = rawName.substring(0, pipe).trim();
  final String right = rawName.substring(pipe + 1).trim();
  final String name =
      left.isEmpty ? "(unnamed)" : left.split(RegExp(r"\s+")).last;
  return TestRow(name, right);
}

/// Reduces a multi-line expectation failure to one readable line.
String _squash(String message) {
  final List<String> lines = message
      .split("\n")
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return "no message";

  final String expected = lines.firstWhere(
    (String l) => l.startsWith("Expected:"),
    orElse: () => "",
  );
  final String actual = lines.firstWhere(
    (String l) => l.startsWith("Actual:"),
    orElse: () => "",
  );

  if (expected.isNotEmpty && actual.isNotEmpty) {
    return "$expected / $actual";
  }
  return lines.first;
}

/// True for error text that says nothing a reader can act on.
bool _isUseless(String reason) =>
    reason.startsWith("Test failed. See exception logs");

/// Pulls the real expectation out of a widget test's console dump.
///
/// The dump is a banner, then a "The following X was thrown" line, then the
/// substance. The Expected/Actual pair is what a reader wants; failing that,
/// the first line of substance will do.
String _reasonFromDump(String dump) {
  final List<String> lines = dump
      .split("\n")
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .where((String l) => !l.startsWith("═") && !l.startsWith("◢"))
      .toList();
  if (lines.isEmpty) return "";

  final String expected = lines.firstWhere(
    (String l) => l.startsWith("Expected:"),
    orElse: () => "",
  );
  final String actual = lines.firstWhere(
    (String l) => l.startsWith("Actual:"),
    orElse: () => "",
  );
  if (expected.isNotEmpty && actual.isNotEmpty) return "$expected / $actual";

  final int thrown = lines.indexWhere((String l) => l.contains(" was thrown"));
  if (thrown != -1 && thrown + 1 < lines.length) return lines[thrown + 1];

  return lines.first;
}

/// Why the integration suite cannot run, or null if it can.
Future<String?> _integrationBlocker(String device) async {
  final ProcessResult devices = await Process.run(
    Platform.isWindows ? "flutter.bat" : "flutter",
    <String>["devices", "--machine"],
    runInShell: true,
  );
  final String output = "${devices.stdout}";
  if (!output.contains(device)) {
    return "device $device not connected";
  }
  return null;
}

void _printTable(List<TestRow> rows, Duration elapsed) {
  if (rows.isEmpty) {
    stdout.writeln("No tests ran.");
    return;
  }

  const int nameWidth = 34;
  const int descWidth = 46;

  final String header =
      "${_pad("NAME", nameWidth)}  ${_pad("DESCRIPTION", descWidth)}  RESULT  REASON";

  stdout.writeln("");
  stdout.writeln(header);

  for (final TestRow row in rows) {
    final String reason = row.result == "PASS" ? "-" : row.reason;
    stdout.writeln("${_pad(row.name, nameWidth)}  "
        "${_pad(row.description, descWidth)}  "
        "${_pad(row.result, 6)}  ${_clip(reason, 70)}");
  }

  final int passed = rows.where((TestRow r) => r.result == "PASS").length;
  final int failed = rows.where((TestRow r) => r.result == "FAIL").length;
  final int skipped = rows.where((TestRow r) => r.result == "SKIP").length;
  final String seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);

  stdout.writeln("-" * 100);
  stdout.writeln(
      "$passed passed, $failed failed, $skipped skipped in ${seconds}s");
  if (failed > 0) stdout.writeln("Details: $_reportDir/last_run.json");
}

String _pad(String value, int width) => _clip(value, width).padRight(width);

String _clip(String value, int width) =>
    value.length <= width ? value : "${value.substring(0, width - 1)}…";

void _writeReport(List<TestRow> rows, Duration elapsed) {
  final Directory dir = Directory(_reportDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final Map<String, dynamic> report = {
    "generated_at": DateTime.now().toIso8601String(),
    "duration_seconds": elapsed.inMilliseconds / 1000,
    "passed": rows.where((TestRow r) => r.result == "PASS").length,
    "failed": rows.where((TestRow r) => r.result == "FAIL").length,
    "skipped": rows.where((TestRow r) => r.result == "SKIP").length,
    "tests": rows.map((TestRow r) => r.toJson()).toList(),
  };

  File("$_reportDir/last_run.json")
      .writeAsStringSync(const JsonEncoder.withIndent("  ").convert(report));
}
