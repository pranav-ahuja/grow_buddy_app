/// Phone login end to end, including the profile screen it lands on.
///
/// There is no SMS provider, so this leans on `OTP_DEBUG_RETURN=true`, which
/// returns the code in the API response and makes the app print it in a
/// SnackBar. That setting is the only reason phone login is testable at all
/// before an SMS contract is signed.
///
/// Every test here requests a code exactly once. The backend allows one request
/// per number per 30 seconds, so asking a second time — even to read the code
/// back — earns a 429 and no code.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CompleteProfile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Verify.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pinput/pinput.dart';

import 'e2e_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late bool backendUp;

  setUpAll(() async {
    backendUp = await backendIsReachable();
  });

  setUp(resetDevice);

  /// Walks onboarding to the phone screen, asks for a code, and returns the one
  /// the app printed. [localDigits] is the number without its country code.
  Future<String?> requestCodeFor(
    WidgetTester tester,
    String localDigits,
  ) async {
    await launchApp(tester);
    await tapAndSettle(tester, find.byType(FloatingActionButton));

    // The phone button is the last of the four in the dialog.
    await tapAndSettle(tester, find.byType(ElevatedButton).last);
    expect(find.byType(GB_MobileLogin), findsOneWidget);

    await enterText(tester, find.byType(IntlPhoneField), localDigits);
    await tester.tap(buttonWithText("Next"));

    final String? code = await pumpForDevCode(tester);
    await settle(tester);
    return code;
  }

  /// Skips with a clear reason rather than failing on a null.
  void requireCode(String? code) {
    if (code == null) {
      markTestSkipped(
        "No dev code appeared. Set OTP_DEBUG_RETURN=true in backend/.env - "
        "phone login cannot be tested without it.",
      );
    }
  }

  testWidgets("e2e_otp_requests_a_code | The phone screen reaches OTP entry",
      (WidgetTester tester) async {
    if (!backendUp) {
      markTestSkipped(backendUnreachableReason);
      return;
    }

    final String phone = uniquePhone();
    await requestCodeFor(tester, phone.substring(3));

    expect(find.byType(GB_Verify), findsOneWidget);
    expect(find.textContaining(phone), findsOneWidget);
  });

  testWidgets("e2e_otp_verifies_and_creates_an_account | A new number becomes a user",
      (WidgetTester tester) async {
    if (!backendUp) {
      markTestSkipped(backendUnreachableReason);
      return;
    }

    final String phone = uniquePhone();
    final String? code = await requestCodeFor(tester, phone.substring(3));
    requireCode(code);
    if (code == null) return;

    await enterText(tester, find.byType(Pinput), code);
    await settle(tester);

    // A phone sign-in cannot say teacher or student, so the backend sends
    // needs_account_type and the app must go and ask.
    expect(find.byType(GB_CompleteProfile), findsOneWidget);
    expect(gLoginToken, isNotNull);
    expect(gCurrentUser!.phone, phone);
    expect(gCurrentUser!.isPhoneVerified, isTrue);
  });

  testWidgets("e2e_otp_rejects_a_wrong_code | A bad code does not sign anyone in",
      (WidgetTester tester) async {
    if (!backendUp) {
      markTestSkipped(backendUnreachableReason);
      return;
    }

    final String phone = uniquePhone();
    await requestCodeFor(tester, phone.substring(3));

    await enterText(tester, find.byType(Pinput), "000000");
    await settle(tester);

    expect(find.byType(GB_Verify), findsOneWidget);
    expect(gLoginToken, isNull);
  });

  testWidgets("e2e_otp_completes_a_profile | Picking a role opens the dashboard",
      (WidgetTester tester) async {
    if (!backendUp) {
      markTestSkipped(backendUnreachableReason);
      return;
    }

    final String phone = uniquePhone();
    final String? code = await requestCodeFor(tester, phone.substring(3));
    requireCode(code);
    if (code == null) return;

    await enterText(tester, find.byType(Pinput), code);
    await settle(tester);
    expect(find.byType(GB_CompleteProfile), findsOneWidget);

    // The placeholder name is deliberately not prefilled, so this is a real
    // entry rather than an accepted default.
    await enterText(tester, fieldWithLabel("Full Name"), "Tastu Phone User");
    await tapAndSettle(tester, find.text("Teacher"));
    await tapAndSettle(tester, buttonWithText("Continue"));

    expect(find.byType(GB_TeacherDashboard), findsOneWidget);
    expect(gCurrentUser!.role, "teacher");
    expect(gCurrentUser!.needsAccountType, isFalse);
  });
}
