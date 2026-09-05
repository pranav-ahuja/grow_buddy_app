/// Phone-number entry, and the OTP request it kicks off.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Verify.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../support/harness.dart';
import '../support/mock_api.dart';

/// What the backend answers a code request with in development.
Map<String, dynamic> _otpSent({String? debugOtp = "123456"}) => {
      "message": "Verification code sent",
      "expires_in_seconds": 300,
      if (debugOtp != null) "debug_otp": debugOtp,
    };

void main() {
  late FakeApi api;

  setUp(() => api = startTest());
  tearDown(endTest);

  Future<void> pumpMobileLogin(WidgetTester tester) =>
      pumpScreen(tester, const GB_MobileLogin());

  Future<void> typeNumber(WidgetTester tester, String digits) async {
    await enterText(tester, find.byType(IntlPhoneField), digits);
  }

  testWidgets("phone_renders | The number field and Next button are shown",
      (WidgetTester tester) async {
    await pumpMobileLogin(tester);

    expect(find.byType(IntlPhoneField), findsOneWidget);
    expect(buttonWithText("Next"), findsOneWidget);
    expect(find.text("Enter your Mobile Number"), findsOneWidget);
  });

  testWidgets("phone_requires_a_number | An empty field never calls the server",
      (WidgetTester tester) async {
    await pumpMobileLogin(tester);

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(currentSnackBarText(tester), "Please enter your mobile number");
    expect(api.madeNoCalls, isTrue);
  });

  testWidgets("phone_sends_complete_number | The country code travels with it",
      (WidgetTester tester) async {
    // The regression this screen is remembered for: the number was captured as
    // value.toString(), which is the PhoneNumber object's description, so what
    // reached the server could never have been a phone number at all. It must
    // be completeNumber, in E.164 form.
    api.stub("/auth/otp/request", body: _otpSent());
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(api.requestTo("/auth/otp/request").body, {"phone": "+919876543210"});
  });

  testWidgets("phone_defaults_to_india | The initial country code is +91",
      (WidgetTester tester) async {
    api.stub("/auth/otp/request", body: _otpSent());
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9000000001");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(
      api.requestTo("/auth/otp/request").body["phone"],
      startsWith("+91"),
    );
  });

  testWidgets("phone_opens_verify | A sent code moves on to OTP entry",
      (WidgetTester tester) async {
    api.stub("/auth/otp/request", body: _otpSent());
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(find.byType(GB_Verify), findsOneWidget);
  });

  testWidgets("phone_passes_number_forward | Verify is told which number to use",
      (WidgetTester tester) async {
    // The verify screen has no way to ask, so a wrong number here would make
    // every code fail with no clue why.
    api.stub("/auth/otp/request", body: _otpSent());
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(
      tester.widget<GB_Verify>(find.byType(GB_Verify)).phoneNumber,
      "+919876543210",
    );
  });

  testWidgets("phone_shows_dev_code | The debug code is surfaced for testing",
      (WidgetTester tester) async {
    // There is no SMS provider yet, so this SnackBar is the only way a tester
    // ever sees the code. Debug builds only.
    api.stub("/auth/otp/request", body: _otpSent(debugOtp: "654321"));
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(currentSnackBarText(tester), contains("dev code: 654321"));
  });

  testWidgets("phone_shows_rate_limit | A 429 reaches the user unchanged",
      (WidgetTester tester) async {
    api.stubError("/auth/otp/request",
        status: 429, detail: "Please wait before requesting another code");
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(currentSnackBarText(tester),
        "Please wait before requesting another code");
    expect(find.byType(GB_Verify), findsNothing);
  });

  testWidgets("phone_stays_put_on_error | A rejected number does not move on",
      (WidgetTester tester) async {
    api.stubError("/auth/otp/request",
        status: 422, detail: "Enter a valid phone number, e.g. +919876543210");
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tapAndSettle(tester, buttonWithText("Next"));

    expect(find.byType(GB_MobileLogin), findsOneWidget);
    expect(find.byType(GB_Verify), findsNothing);
  });

  testWidgets("phone_disables_button_while_sending | No double requests",
      (WidgetTester tester) async {
    api.stub("/auth/otp/request",
        body: _otpSent(), delay: const Duration(milliseconds: 400));
    await pumpMobileLogin(tester);
    await typeNumber(tester, "9876543210");

    await tester.tap(buttonWithText("Next"));
    await tester.pump();

    expect(buttonWithText("Sending..."), findsOneWidget);
    expect(isButtonDisabled(tester, "Sending..."), isTrue);

    await pumpFrames(tester, times: 8);
  });

  testWidgets("phone_to_signup | The sign-up link works from here too",
      (WidgetTester tester) async {
    await pumpMobileLogin(tester);

    await tapAndSettle(tester, find.text("New to Grow Buddy? Sign up now"));

    expect(find.byType(GB_SignUp), findsOneWidget);
  });
}
