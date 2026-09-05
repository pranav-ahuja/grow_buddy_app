/// OTP entry. The code box auto-submits on the sixth digit, so most of these
/// never press Confirm at all — which is exactly how a user experiences it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Verify.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:pinput/pinput.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/mock_api.dart';

const String _phone = "+919876543210";

void main() {
  late FakeApi api;

  setUp(() => api = startTest());
  tearDown(endTest);

  Future<void> pumpVerify(WidgetTester tester) =>
      pumpScreen(tester, const GB_Verify(phoneNumber: _phone));

  Future<void> typeCode(WidgetTester tester, String code) async {
    await enterText(tester, find.byType(Pinput), code);
  }

  testWidgets("otp_renders | The code box and both buttons are shown",
      (WidgetTester tester) async {
    await pumpVerify(tester);

    expect(find.byType(Pinput), findsOneWidget);
    expect(buttonWithText("Confirm"), findsOneWidget);
    expect(buttonWithText("Resend Code"), findsOneWidget);
  });

  testWidgets("otp_shows_the_number | The screen says which number was texted",
      (WidgetTester tester) async {
    await pumpVerify(tester);

    expect(find.textContaining(_phone), findsOneWidget);
  });

  testWidgets("otp_requires_a_code | Confirming an empty box is refused",
      (WidgetTester tester) async {
    await pumpVerify(tester);

    await tapAndSettle(tester, buttonWithText("Confirm"));

    expect(currentSnackBarText(tester), "Please enter the code we sent you");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("otp_rejects_a_short_code | Three digits is not a code",
      (WidgetTester tester) async {
    await pumpVerify(tester);
    await typeCode(tester, "123");

    await tapAndSettle(tester, buttonWithText("Confirm"));

    expect(currentSnackBarText(tester), "Please enter the code we sent you");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("otp_autosubmits_on_sixth_digit | Completing the box verifies",
      (WidgetTester tester) async {
    api.stub("/auth/otp/verify",
        body: tokenJson(isNewUser: true, user: needsRoleUserJson()));
    await pumpVerify(tester);

    await typeCode(tester, "123456");
    await pumpFrames(tester);

    expect(api.called("/auth/otp/verify"), isTrue);
  });

  testWidgets("otp_sends_phone_and_code | Both halves reach the server",
      (WidgetTester tester) async {
    api.stub("/auth/otp/verify",
        body: tokenJson(user: needsRoleUserJson()));
    await pumpVerify(tester);

    await typeCode(tester, "123456");
    await pumpFrames(tester);

    expect(api.requestTo("/auth/otp/verify").body, {
      "phone": _phone,
      "otp": "123456",
    });
  });

  testWidgets("otp_new_user_completes_profile | A phone sign-up has no role yet",
      (WidgetTester tester) async {
    // Phone sign-in cannot say teacher or student, so the backend sends
    // needs_account_type and the app must go and ask.
    api.stub("/auth/otp/verify",
        body: tokenJson(isNewUser: true, user: needsRoleUserJson()));
    await pumpVerify(tester);

    await typeCode(tester, "123456");
    await pumpFrames(tester);

    expect(find.byType(GB_CompleteProfile), findsOneWidget);
  });

  testWidgets("otp_returning_user_opens_dashboard | A known role skips the ask",
      (WidgetTester tester) async {
    api.stub("/auth/otp/verify", body: tokenJson());
    await pumpVerify(tester);

    await typeCode(tester, "123456");
    await pumpFrames(tester);

    expect(find.byType(GB_Dashboard), findsOneWidget);
    expect(gLoginToken, kTestToken);
  });

  testWidgets("otp_wrong_code_shows_error | The server wording reaches the user",
      (WidgetTester tester) async {
    api.stubError("/auth/otp/verify",
        status: 400, detail: "That code is not correct");
    await pumpVerify(tester);

    await typeCode(tester, "111111");
    await pumpFrames(tester);

    expect(currentSnackBarText(tester), "That code is not correct");
    expect(find.byType(GB_Verify), findsOneWidget);
  });

  testWidgets("otp_clears_after_a_wrong_code | The box is emptied to retype",
      (WidgetTester tester) async {
    // Leaving the wrong digits in place would mean the user has to delete six
    // characters before their second attempt.
    api.stubError("/auth/otp/verify", status: 400, detail: "Wrong code");
    await pumpVerify(tester);

    await typeCode(tester, "111111");
    await pumpFrames(tester);

    expect(
      tester.widget<Pinput>(find.byType(Pinput)).controller!.text,
      isEmpty,
    );
  });

  testWidgets("otp_expired_code_is_reported | An expired code says so",
      (WidgetTester tester) async {
    api.stubError("/auth/otp/verify",
        status: 400, detail: "That code has expired. Request a new one.");
    await pumpVerify(tester);

    await typeCode(tester, "123456");
    await pumpFrames(tester);

    expect(currentSnackBarText(tester),
        "That code has expired. Request a new one.");
  });

  testWidgets("otp_resend_requests_a_new_code | Resend hits otp/request",
      (WidgetTester tester) async {
    api.stub("/auth/otp/request", body: {
      "message": "Verification code sent",
      "expires_in_seconds": 300,
      "debug_otp": "999888",
    });
    await pumpVerify(tester);

    await tapAndSettle(tester, buttonWithText("Resend Code"));

    expect(api.requestTo("/auth/otp/request").body, {"phone": _phone});
    expect(currentSnackBarText(tester), contains("dev code: 999888"));
  });

  testWidgets("otp_resend_respects_rate_limit | A 429 is shown, not swallowed",
      (WidgetTester tester) async {
    api.stubError("/auth/otp/request",
        status: 429, detail: "Please wait before requesting another code");
    await pumpVerify(tester);

    await tapAndSettle(tester, buttonWithText("Resend Code"));

    expect(currentSnackBarText(tester),
        "Please wait before requesting another code");
  });
}
