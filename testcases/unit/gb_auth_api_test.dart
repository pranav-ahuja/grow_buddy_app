/// GB_AuthApi is the translation layer between the app's vocabulary and the
/// backend's. These tests assert on what the app *sends*, which is what catches
/// a screen posting the wrong field name — a bug no amount of UI clicking finds
/// until the server rejects it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';

import '../support/fixtures.dart';
import '../support/mock_api.dart';

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi();
    api.install();
  });

  tearDown(FakeApi.restore);

  test("signup_sends_contract | Sign-up posts the four fields the server wants",
      () async {
    api.stub("/auth/signup", status: 201, body: tokenJson(isNewUser: true));

    final GB_AuthResult result = await GB_AuthApi.signUp(
      fullName: "Pranav Ahuja",
      identifier: "pranav@example.com",
      password: "supersecret123",
      accountType: 0,
    );

    final RecordedRequest sent = api.requestTo("/auth/signup");
    expect(sent.method, "POST");
    expect(sent.body, {
      "full_name": "Pranav Ahuja",
      "identifier": "pranav@example.com",
      "password": "supersecret123",
      "account_type": 0,
    });
    expect(result.isNewUser, isTrue);
    expect(result.token, kTestToken);
  });

  test("signup_identifier_is_one_field | A phone goes in the same field", () {
    // The sign-up screen has a single "Email id / Phone Number" box and the
    // server decides which it received, so the app must not try to split them.
    api.stub("/auth/signup", status: 201, body: tokenJson());

    expect(
      () => GB_AuthApi.signUp(
        fullName: "X",
        identifier: "+919876543210",
        password: "supersecret123",
        accountType: 1,
      ),
      returnsNormally,
    );
  });

  test("login_sends_contract | Login posts email and password", () async {
    api.stub("/auth/login", body: tokenJson());

    await GB_AuthApi.login(email: "a@b.com", password: "hunter2000");

    expect(api.requestTo("/auth/login").body, {
      "email": "a@b.com",
      "password": "hunter2000",
    });
  });

  test("login_surfaces_server_message | A 401 arrives as the server's wording",
      () async {
    api.stubError("/auth/login",
        status: 401, detail: "Invalid email or password");

    await expectLater(
      () => GB_AuthApi.login(email: "a@b.com", password: "wrong"),
      throwsA(isA<GB_ApiException>().having(
          (GB_ApiException e) => e.message, "message",
          "Invalid email or password")),
    );
  });

  test("otp_request_sends_phone | Requesting a code posts just the number",
      () async {
    api.stub("/auth/otp/request", body: {
      "message": "Verification code sent",
      "expires_in_seconds": 300,
      "debug_otp": "123456",
    });

    final GB_OtpRequestResult result =
        await GB_AuthApi.requestOtp("+919876543210");

    expect(api.requestTo("/auth/otp/request").body, {"phone": "+919876543210"});
    expect(result.debugOtp, "123456");
  });

  test("otp_verify_sends_phone_and_code | Verifying posts both", () async {
    api.stub("/auth/otp/verify", body: tokenJson(user: needsRoleUserJson()));

    final GB_AuthResult result = await GB_AuthApi.verifyOtp(
      phone: "+919876543210",
      otp: "123456",
    );

    expect(api.requestTo("/auth/otp/verify").body, {
      "phone": "+919876543210",
      "otp": "123456",
    });
    // A phone sign-in cannot say teacher or student, so the app must be told to
    // go and ask.
    expect(result.user.needsAccountType, isTrue);
  });

  test("google_sends_id_token | The ID token goes up, never an email",
      () async {
    // Sending an email would let anyone with curl claim any account; the server
    // verifies this token's signature with Google before believing it.
    api.stub("/auth/google", body: tokenJson());

    await GB_AuthApi.loginWithGoogle("eyJhbGciOi.fake.token");

    final RecordedRequest sent = api.requestTo("/auth/google");
    expect(sent.body, {"id_token": "eyJhbGciOi.fake.token"});
    expect(sent.body.containsKey("email"), isFalse);
  });

  test("me_sends_token | The current user is fetched with a bearer token",
      () async {
    api.stub("/auth/me", body: userJson(), method: "GET");

    final GB_User user = await GB_AuthApi.me("jwt-abc");

    expect(api.requestTo("/auth/me").bearerToken, "jwt-abc");
    expect(user.fullName, "Pranav Ahuja");
  });

  test("update_profile_omits_untouched_fields | Only what changed is sent",
      () async {
    // The backend rejects a PATCH that changes nothing, so the app must not
    // pad the body with nulls.
    api.stub("/auth/me", body: userJson(), method: "PATCH");

    await GB_AuthApi.updateProfile(token: "jwt-abc", accountType: 1);

    final RecordedRequest sent = api.requestTo("/auth/me");
    expect(sent.body, {"account_type": 1});
    expect(sent.body.containsKey("full_name"), isFalse);
  });

  test("update_profile_sends_both | Name and role travel together", () async {
    api.stub("/auth/me", body: userJson(), method: "PATCH");

    await GB_AuthApi.updateProfile(
      token: "jwt-abc",
      fullName: "Real Name",
      accountType: 0,
    );

    expect(api.requestTo("/auth/me").body, {
      "full_name": "Real Name",
      "account_type": 0,
    });
  });
}
