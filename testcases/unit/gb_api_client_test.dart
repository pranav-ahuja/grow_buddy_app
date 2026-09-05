/// GB_ApiClient is the only HTTP code in the app, so every screen inherits
/// whatever it gets right or wrong about error handling. These are the
/// highest-value tests in the suite.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

import '../support/mock_api.dart';

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi();
    api.install();
  });

  tearDown(FakeApi.restore);

  test("api_decodes_success | A 2xx JSON body comes back as a map", () async {
    api.stub("/auth/login", body: {"access_token": "abc", "token_type": "bearer"});

    final Map<String, dynamic> result =
        await GB_ApiClient.postJson(kLoginUrl, {"email": "a@b.com"});

    expect(result["access_token"], "abc");
    expect(result["token_type"], "bearer");
  });

  test("api_error_detail | An error's detail becomes the exception message",
      () async {
    api.stubError("/auth/login", status: 401, detail: "Invalid email or password");

    // The backend words its errors for humans and the app shows them verbatim,
    // so the message must survive the trip unchanged.
    await expectLater(
      () => GB_ApiClient.postJson(kLoginUrl, {}),
      throwsA(isA<GB_ApiException>()
          .having((GB_ApiException e) => e.message, "message",
              "Invalid email or password")
          .having((GB_ApiException e) => e.statusCode, "statusCode", 401)),
    );
  });

  test("api_non_json_error | A crash page falls back to a status message",
      () async {
    // A proxy or a 500 page, not our API. Without the fallback the user would
    // see a raw HTML dump in a SnackBar.
    api.stub("/auth/login", status: 500, body: "<html>Bad Gateway</html>");

    await expectLater(
      () => GB_ApiClient.postJson(kLoginUrl, {}),
      throwsA(isA<GB_ApiException>().having(
          (GB_ApiException e) => e.message, "message", "Request failed (500)")),
    );
  });

  test("api_empty_body | An empty 2xx body decodes to an empty map", () async {
    api.stub("/auth/login", body: "");

    expect(await GB_ApiClient.postJson(kLoginUrl, {}), isEmpty);
  });

  test("api_offline | An unreachable server explains itself", () async {
    api.stubThrows("/auth/login", const SocketException("connection refused"));

    await expectLater(
      () => GB_ApiClient.postJson(kLoginUrl, {}),
      throwsA(isA<GB_ApiException>().having(
        (GB_ApiException e) => e.message,
        "message",
        contains("Can't reach the server"),
      )),
    );
  });

  test("api_timeout | A hanging server explains itself", () async {
    // Throws TimeoutException directly rather than stalling for the real 15s
    // timeout: what is under test is the error mapping, not Dart's timer.
    api.stubThrows("/auth/login", TimeoutException("too slow"));

    await expectLater(
      () => GB_ApiClient.postJson(kLoginUrl, {}),
      throwsA(isA<GB_ApiException>().having(
        (GB_ApiException e) => e.message,
        "message",
        contains("took too long"),
      )),
    );
  });

  test("api_sends_bearer_token | A token is sent as an Authorization header",
      () async {
    api.stub("/auth/me", body: {"id": 1});

    await GB_ApiClient.getJson(kMeUrl, token: "jwt-123");

    expect(api.requestTo("/auth/me").bearerToken, "jwt-123");
  });

  test("api_omits_absent_token | No token means no Authorization header",
      () async {
    api.stub("/auth/login", body: {});

    await GB_ApiClient.postJson(kLoginUrl, {});

    expect(api.lastRequest.bearerToken, isNull);
  });

  test("api_json_headers | Every request declares JSON in and out", () async {
    api.stub("/auth/login", body: {});

    await GB_ApiClient.postJson(kLoginUrl, {"email": "a@b.com"});

    final RecordedRequest sent = api.lastRequest;
    expect(sent.headers["content-type"], contains("application/json"));
    expect(sent.headers["accept"], "application/json");
    expect(sent.body["email"], "a@b.com");
  });

  test("api_patch_sends_body | patchJson sends the body and the token",
      () async {
    api.stub("/auth/me", body: {"id": 1}, method: "PATCH");

    await GB_ApiClient.patchJson(kMeUrl, {"account_type": 1}, token: "jwt-9");

    final RecordedRequest sent = api.requestTo("/auth/me");
    expect(sent.method, "PATCH");
    expect(sent.body["account_type"], 1);
    expect(sent.bearerToken, "jwt-9");
  });
}
