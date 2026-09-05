/// A stand-in for the GrowBuddy backend.
///
/// [GB_ApiClient.client] is swapped for a `MockClient`, so the app's real
/// service layer, error unwrapping, and timeout handling all run exactly as
/// they do in production — only the socket is replaced. Tests assert on what
/// the app *sent* as much as on what it did with the reply, which is what
/// catches a screen posting the wrong field name.
library;

// The analyzer only treats test/, integration_test/ and test_driver/ as
// test code, and this suite lives in testcases/ by request. These members
// are annotated @visibleForTesting and this IS the test using them.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';

/// One call the app made.
class RecordedRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String rawBody;

  RecordedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.rawBody,
  });

  /// The decoded JSON body, or `{}` for a GET.
  Map<String, dynamic> get body {
    if (rawBody.isEmpty) return <String, dynamic>{};
    return jsonDecode(rawBody) as Map<String, dynamic>;
  }

  /// The bearer token the app attached, or null if it sent none.
  String? get bearerToken {
    final String? raw = headers["authorization"] ?? headers["Authorization"];
    if (raw == null || !raw.startsWith("Bearer ")) return null;
    return raw.substring("Bearer ".length);
  }

  @override
  String toString() => "$method $url $rawBody";
}

class _Stub {
  final String urlContains;
  final String method;
  final int status;
  final String body;
  final Object? throws;
  final Duration? delay;

  /// Consumed left to right, so a test can queue two different answers for the
  /// same URL — a 401 then a 200, for instance, to test a retry.
  bool used = false;
  final bool once;

  _Stub({
    required this.urlContains,
    required this.method,
    required this.status,
    required this.body,
    this.throws,
    this.delay,
    this.once = false,
  });

  bool matches(http.BaseRequest request) {
    if (once && used) return false;
    if (method != "ANY" && method != request.method) return false;
    return request.url.toString().contains(urlContains);
  }
}

class FakeApi {
  final List<RecordedRequest> requests = <RecordedRequest>[];
  final List<_Stub> _stubs = <_Stub>[];

  /// Answers any request whose URL contains [urlContains] with [body].
  ///
  /// Matching on a substring rather than the full URL keeps tests readable —
  /// `stub("/auth/login", ...)` — and independent of `kApiBaseUrl`, which
  /// changes per machine.
  void stub(
    String urlContains, {
    int status = 200,
    Object body = const <String, dynamic>{},
    String method = "ANY",
    Duration? delay,
    bool once = false,
  }) {
    _stubs.add(_Stub(
      urlContains: urlContains,
      method: method,
      status: status,
      body: body is String ? body : jsonEncode(body),
      delay: delay,
      once: once,
    ));
  }

  /// The backend's error shape, which the app surfaces to the user verbatim.
  void stubError(
    String urlContains, {
    required int status,
    required String detail,
    String method = "ANY",
    bool once = false,
  }) {
    stub(
      urlContains,
      status: status,
      body: {"detail": detail},
      method: method,
      once: once,
    );
  }

  /// Makes the transport itself fail — pass a `SocketException` for "server
  /// unreachable" or a `TimeoutException` for a hang.
  void stubThrows(String urlContains, Object error, {String method = "ANY"}) {
    _stubs.add(_Stub(
      urlContains: urlContains,
      method: method,
      status: 0,
      body: "",
      throws: error,
    ));
  }

  /// Installs this fake as the app's HTTP client. Pair with [restore].
  void install() {
    GB_ApiClient.client = MockClient(_handle);
  }

  /// Puts the real client back, so one test's fake can never leak into another.
  static void restore() {
    GB_ApiClient.client = http.Client();
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(RecordedRequest(
      method: request.method,
      url: request.url,
      headers: request.headers,
      rawBody: request.body,
    ));

    for (final _Stub stub in _stubs) {
      if (!stub.matches(request)) continue;
      stub.used = true;

      if (stub.delay != null) await Future<void>.delayed(stub.delay!);
      if (stub.throws != null) throw stub.throws!;

      return http.Response(
        stub.body,
        stub.status,
        headers: {"content-type": "application/json"},
      );
    }

    // Not an exception: GB_ApiClient would wrap a throw as a generic "Network
    // error", burying the cause. A 599 travels through the real error path and
    // arrives in the test as a message naming the URL that needs a stub.
    return http.Response(
      jsonEncode({
        "detail": "No stub for ${request.method} ${request.url} — "
            "add fakeApi.stub(...) in the test",
      }),
      599,
      headers: {"content-type": "application/json"},
    );
  }

  /// How many calls the app made in total.
  int get callCount => requests.length;

  /// True when the app called nothing at all — what the unwired
  /// forgot-password screens must satisfy.
  bool get madeNoCalls => requests.isEmpty;

  RecordedRequest get lastRequest {
    if (requests.isEmpty) {
      throw StateError("The app made no HTTP calls at all");
    }
    return requests.last;
  }

  /// The single call to a URL containing [urlContains].
  RecordedRequest requestTo(String urlContains) {
    final List<RecordedRequest> hits = requests
        .where((RecordedRequest r) => r.url.toString().contains(urlContains))
        .toList();
    if (hits.isEmpty) {
      throw StateError(
        "No request to '$urlContains'. Calls made: "
        "${requests.map((RecordedRequest r) => '${r.method} ${r.url.path}').join(', ')}",
      );
    }
    return hits.last;
  }

  /// Whether the app called [urlContains] at all.
  bool called(String urlContains) => requests
      .any((RecordedRequest r) => r.url.toString().contains(urlContains));
}
