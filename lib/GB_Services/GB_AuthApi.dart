import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

class GB_User {
  final int id;
  final String fullName;
  final String? email;
  final String? phone;

  /// Null when the account came from Google or phone sign-in, neither of which
  /// tells the backend whether the person is a teacher or a student.
  final int? accountType;
  final String? role;

  /// True while [accountType] is null — send the user to the "Who are you?"
  /// screen, then call [GB_AuthApi.setAccountType].
  final bool needsAccountType;

  final bool isPhoneVerified;

  GB_User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.accountType,
    required this.role,
    required this.needsAccountType,
    required this.isPhoneVerified,
  });

  factory GB_User.fromJson(Map<String, dynamic> json) {
    return GB_User(
      id: json["id"] as int,
      fullName: json["full_name"] as String,
      email: json["email"] as String?,
      phone: json["phone"] as String?,
      accountType: json["account_type"] as int?,
      role: json["role"] as String?,
      needsAccountType: json["needs_account_type"] as bool? ?? false,
      isPhoneVerified: json["is_phone_verified"] as bool? ?? false,
    );
  }

  /// Deliberately mirrors the backend's field names so [fromJson] can read back
  /// what this writes — the cached copy and an API response are the same shape.
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "full_name": fullName,
      "email": email,
      "phone": phone,
      "account_type": accountType,
      "role": role,
      "needs_account_type": needsAccountType,
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

  /// Completes a profile after a Google or phone sign-up.
  ///
  /// Pass whichever fields the sign-up screen collected; omitted fields are
  /// left untouched. The backend rejects a call that changes nothing.
  static Future<GB_User> updateProfile({
    required String token,
    String? fullName,
    int? accountType,
  }) async {
    final json = await GB_ApiClient.patchJson(
      kMeUrl,
      {
        if (fullName != null) "full_name": fullName,
        if (accountType != null) "account_type": accountType,
      },
      token: token,
    );
    return GB_User.fromJson(json);
  }

  static Future<GB_User> me(String token) async {
    final json = await GB_ApiClient.getJson(kMeUrl, token: token);
    return GB_User.fromJson(json);
  }
}
