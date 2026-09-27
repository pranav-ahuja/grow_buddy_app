import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

class GB_User {
  /// The server's user id, e.g. "U_000001".
  final String userId;
  final String fullName;
  final String? email;
  final String? phone;

  /// Null when the account came from Google or phone sign-in, neither of which
  /// tells the backend whether the person is a teacher or a student.
  final int? accountType;
  final String? role;

  /// True while [accountType] is null — send the user to the "Who are you?"
  /// screen, then call [GB_AuthApi.updateProfile].
  final bool needsAccountType;

  /// True while [email] or [phone] is missing. Every user has both: signing up
  /// with one, the profile screen asks for the other.
  final bool needsContactDetails;

  final bool isPhoneVerified;

  GB_User({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.accountType,
    required this.role,
    required this.needsAccountType,
    required this.needsContactDetails,
    required this.isPhoneVerified,
  });

  /// Whether sign-in should detour through the profile screen before the
  /// dashboard — for a missing role or a missing email or phone number.
  bool get needsProfileCompletion => needsAccountType || needsContactDetails;

  factory GB_User.fromJson(Map<String, dynamic> json) {
    final String? email = json["email"] as String?;
    final String? phone = json["phone"] as String?;
    return GB_User(
      userId: json["user_id"] as String,
      fullName: json["full_name"] as String,
      email: email,
      phone: phone,
      accountType: json["account_type"] as int?,
      role: json["role"] as String?,
      needsAccountType: json["needs_account_type"] as bool? ?? false,
      // Worked out locally when absent, so a session cached before this field
      // existed still gets asked for the missing contact.
      needsContactDetails:
          json["needs_contact_details"] as bool? ?? (email == null || phone == null),
      isPhoneVerified: json["is_phone_verified"] as bool? ?? false,
    );
  }

  /// Deliberately mirrors the backend's field names so [fromJson] can read back
  /// what this writes — the cached copy and an API response are the same shape.
  Map<String, dynamic> toJson() {
    return {
      "user_id": userId,
      "full_name": fullName,
      "email": email,
      "phone": phone,
      "account_type": accountType,
      "role": role,
      "needs_account_type": needsAccountType,
      "needs_contact_details": needsContactDetails,
      "is_phone_verified": isPhoneVerified,
    };
  }
}

/// A successful sign-up, login, OTP verification, or Google sign-in.
class GB_AuthResult {
  final String token;
  final GB_User user;

  /// True when this call created the account rather than signing in to an
  /// existing one — the cue to show the profile-completion flow.
  final bool isNewUser;

  GB_AuthResult({
    required this.token,
    required this.user,
    required this.isNewUser,
  });

  factory GB_AuthResult.fromJson(Map<String, dynamic> json) {
    return GB_AuthResult(
      token: json["access_token"] as String,
      user: GB_User.fromJson(json["user"] as Map<String, dynamic>),
      isNewUser: json["is_new_user"] as bool? ?? false,
    );
  }
}

class GB_OtpRequestResult {
  final String message;
  final int expiresInSeconds;

  /// Only sent while the backend runs with OTP_DEBUG_RETURN=true, so phone
  /// login can be tested before an SMS provider exists. Null in production.
  final String? debugOtp;

  GB_OtpRequestResult({
    required this.message,
    required this.expiresInSeconds,
    this.debugOtp,
  });

  factory GB_OtpRequestResult.fromJson(Map<String, dynamic> json) {
    return GB_OtpRequestResult(
      message: json["message"] as String? ?? "Verification code sent",
      expiresInSeconds: json["expires_in_seconds"] as int? ?? 300,
      debugOtp: json["debug_otp"] as String?,
    );
  }

  /// What to put in the SnackBar after requesting a code.
  ///
  /// The code is appended only in a debug build. The backend is not supposed to
  /// send [debugOtp] outside development at all — but until real SMS exists,
  /// the whole login flow depends on that field, so a misconfigured server is a
  /// live possibility. [kDebugMode] is the half of the check that a release
  /// build carries with it and a server setting cannot undo, so an OTP can
  /// never be printed on a user's screen no matter how the backend is set up.
  String get displayMessage {
    if (kDebugMode && debugOtp != null) {
      return "$message (dev code: $debugOtp)";
    }
    return message;
  }
}

/// A code sent to an email or number the user is moving their account to.
///
/// Extends [GB_OtpRequestResult] rather than repeating it, so `displayMessage`
/// — and with it the [kDebugMode] guard that keeps a dev code off a real user's
/// screen — has one definition for both flows.
class GB_ContactChangeResult extends GB_OtpRequestResult {
  /// "phone" or "email": which contact this code will change when redeemed.
  final String channel;

  /// The value the server stored and sent the code to, normalised — so the
  /// code screen can name the number the server has, not the one the field
  /// happens to still hold.
  final String value;

  GB_ContactChangeResult({
    required this.channel,
    required this.value,
    required super.message,
    required super.expiresInSeconds,
    super.debugOtp,
  });

  factory GB_ContactChangeResult.fromJson(Map<String, dynamic> json) {
    return GB_ContactChangeResult(
      channel: json["channel"] as String? ?? kContactChannelPhone,
      value: json["value"] as String? ?? "",
      message: json["message"] as String? ?? "Verification code sent",
      expiresInSeconds: json["expires_in_seconds"] as int? ?? 300,
      debugOtp: json["debug_otp"] as String?,
    );
  }
}
class GB_AuthApi {
  /// [identifier] is either an email address or a phone number — the backend
  /// works out which, so the single sign-up field maps straight through.
  static Future<GB_AuthResult> signUp({
    required String fullName,
    required String identifier,
    required String password,
    required int accountType,
  }) async {
    final json = await GB_ApiClient.postJson(kSignUpUrl, {
      "full_name": fullName,
      "identifier": identifier,
      "password": password,
      "account_type": accountType,
    });
    return GB_AuthResult.fromJson(json);
  }

  static Future<GB_AuthResult> login({
    required String email,
    required String password,
  }) async {
    final json = await GB_ApiClient.postJson(kLoginUrl, {
      "email": email,
      "password": password,
    });
    return GB_AuthResult.fromJson(json);
  }

  static Future<GB_OtpRequestResult> requestOtp(String phone) async {
    final json = await GB_ApiClient.postJson(kOtpRequestUrl, {"phone": phone});
    return GB_OtpRequestResult.fromJson(json);
  }

  static Future<GB_AuthResult> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final json = await GB_ApiClient.postJson(kOtpVerifyUrl, {
      "phone": phone,
      "otp": otp,
    });
    return GB_AuthResult.fromJson(json);
  }

  /// Exchanges a Google ID token for a GrowBuddy session.
  ///
  /// [idToken] must be the ID token from the google_sign_in plugin, not an
  /// email — the backend verifies its signature with Google before trusting
  /// anything inside it.
  static Future<GB_AuthResult> loginWithGoogle(String idToken) async {
    final json = await GB_ApiClient.postJson(kGoogleLoginUrl, {
      "id_token": idToken,
    });
    return GB_AuthResult.fromJson(json);
  }

  /// Completes a profile after sign-up: a name and role after Google or phone
  /// sign-in, and whichever of [email] and [phone] the user did not sign up
  /// with.
  ///
  /// Pass whichever fields the profile screen collected; omitted fields are
  /// left untouched. The backend rejects a call that changes nothing, and
  /// answers 409 when the email or phone already belongs to another account.
  static Future<GB_User> updateProfile({
    required String token,
    String? fullName,
    int? accountType,
    String? email,
    String? phone,
  }) async {
    final json = await GB_ApiClient.patchJson(
      kMeUrl,
      {
        if (fullName != null) "full_name": fullName,
        if (accountType != null) "account_type": accountType,
        if (email != null) "email": email,
        if (phone != null) "phone": phone,
      },
      token: token,
    );
    return GB_User.fromJson(json);
  }

  static Future<GB_User> me(String token) async {
    final json = await GB_ApiClient.getJson(kMeUrl, token: token);
    return GB_User.fromJson(json);
  }

  /// Asks the server to send a code to an email or number the signed-in user
  /// wants to move to.
  ///
  /// **Nothing has changed on the account when this returns.** The value is
  /// held server-side until [verifyContactChange] redeems the code, so the
  /// user still signs in with their old contact until then — which is why the
  /// UI must not show the new one as though it were theirs yet.
  ///
  /// Throws [GB_ApiException] on 400 (it is already your number), 409 (someone
  /// else has it) or 429 (inside the resend cooldown); the message is written
  /// for the user.
  static Future<GB_ContactChangeResult> requestContactChange({
    required String token,
    required String channel,
    required String value,
  }) async {
    final json = await GB_ApiClient.postJson(
      kContactChangeRequestUrl,
      {"channel": channel, "value": value},
      token: token,
    );
    return GB_ContactChangeResult.fromJson(json);
  }

  /// Redeems the code and returns the user as they now are — with the new
  /// contact on the account, and `is_phone_verified` true for a number.
  ///
  /// The new value is deliberately **not** a parameter: the server commits the
  /// value the code was issued for, so there is nothing here that could
  /// disagree with what was confirmed.
  static Future<GB_User> verifyContactChange({
    required String token,
    required String channel,
    required String otp,
  }) async {
    final json = await GB_ApiClient.postJson(
      kContactChangeVerifyUrl,
      {"channel": channel, "otp": otp},
      token: token,
    );
    return GB_User.fromJson(json);
  }
}
