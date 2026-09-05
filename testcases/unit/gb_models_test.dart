/// The models are the contract with the backend. A field renamed on the server
/// shows up here as a failing test rather than as a blank dashboard.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';

import '../support/fixtures.dart';

void main() {
  group("GB_User", () {
    test("user_parses_full_payload | Every backend field maps to a property",
        () {
      final GB_User user = GB_User.fromJson(userJson());

      expect(user.id, 1);
      expect(user.fullName, "Pranav Ahuja");
      expect(user.email, "pranav@example.com");
      expect(user.phone, isNull);
      expect(user.accountType, 0);
      expect(user.role, "teacher");
      expect(user.needsAccountType, isFalse);
      expect(user.isPhoneVerified, isFalse);
    });

    test("user_allows_null_identifiers | A phone user has no email", () {
      final GB_User phoneUser = GB_User.fromJson(needsRoleUserJson());

      expect(phoneUser.email, isNull);
      expect(phoneUser.phone, "+919000000001");
      expect(phoneUser.accountType, isNull);
      expect(phoneUser.role, isNull);
      expect(phoneUser.needsAccountType, isTrue);
    });

    test("user_defaults_missing_flags | Absent booleans default to false", () {
      // An older backend, or a cached user written by an earlier build, may not
      // carry these at all. Defaulting beats throwing on a launch path.
      final GB_User user = GB_User.fromJson({
        "id": 7,
        "full_name": "Minimal",
        "email": null,
        "phone": null,
        "account_type": null,
        "role": null,
      });

      expect(user.needsAccountType, isFalse);
      expect(user.isPhoneVerified, isFalse);
    });

    test("user_round_trips | toJson writes what fromJson can read back", () {
      // This is what makes the secure-storage cache work: the cached copy and
      // an API response are deliberately the same shape.
      final GB_User original =
          GB_User.fromJson(userJson(phone: "+911234567890"));
      final GB_User restored = GB_User.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.fullName, original.fullName);
      expect(restored.email, original.email);
      expect(restored.phone, original.phone);
      expect(restored.accountType, original.accountType);
      expect(restored.role, original.role);
      expect(restored.needsAccountType, original.needsAccountType);
      expect(restored.isPhoneVerified, original.isPhoneVerified);
    });
  });

  group("GB_AuthResult", () {
    test("auth_result_parses | Token and nested user both come through", () {
      final GB_AuthResult result =
          GB_AuthResult.fromJson(tokenJson(isNewUser: true));

      expect(result.token, kTestToken);
      expect(result.isNewUser, isTrue);
      expect(result.user.fullName, "Pranav Ahuja");
    });

    test("auth_result_defaults_is_new_user | A missing is_new_user is false",
        () {
      final GB_AuthResult result = GB_AuthResult.fromJson({
        "access_token": "t",
        "user": userJson(),
      });

      expect(result.isNewUser, isFalse);
    });
  });

  group("GB_OtpRequestResult", () {
    test("otp_result_parses | Message, expiry, and debug code all map", () {
      final GB_OtpRequestResult result = GB_OtpRequestResult.fromJson({
        "message": "Verification code sent",
        "expires_in_seconds": 300,
        "debug_otp": "123456",
      });

      expect(result.message, "Verification code sent");
      expect(result.expiresInSeconds, 300);
      expect(result.debugOtp, "123456");
    });

    test("otp_result_defaults | Missing fields fall back sensibly", () {
      final GB_OtpRequestResult result = GB_OtpRequestResult.fromJson({});

      expect(result.message, "Verification code sent");
      expect(result.expiresInSeconds, 300);
      expect(result.debugOtp, isNull);
    });

    test("otp_shows_dev_code_in_debug | The dev code is appended for testing",
        () {
      // Tests run in debug, which is the half of the check the app controls.
      // A release build can never print the code no matter what the server
      // sends, which is the point of the kDebugMode guard.
      final GB_OtpRequestResult result = GB_OtpRequestResult.fromJson({
        "message": "Code sent",
        "debug_otp": "654321",
      });

      expect(result.displayMessage, "Code sent (dev code: 654321)");
    });

    test("otp_hides_absent_code | With no code the message is untouched", () {
      final GB_OtpRequestResult result =
          GB_OtpRequestResult.fromJson({"message": "Code sent"});

      expect(result.displayMessage, "Code sent");
    });
  });
}
