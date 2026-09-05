/// Canned backend payloads.
///
/// Every shape here mirrors what `backend/app/schemas.py` actually returns, so
/// a contract change on the server shows up as failing tests rather than as a
/// UI that quietly renders nothing.
library;

const String kTestToken = "test.jwt.token";

/// A `UserOut` from the backend.
///
/// Defaults describe the common case — an email/password teacher — and every
/// field is overridable so a test can express exactly the one thing it cares
/// about instead of restating the whole object.
Map<String, dynamic> userJson({
  int id = 1,
  String fullName = "Pranav Ahuja",
  String? email = "pranav@example.com",
  String? phone,
  int? accountType = 0,
  String? role = "teacher",
  bool needsAccountType = false,
  bool isPhoneVerified = false,
}) {
  return {
    "id": id,
    "full_name": fullName,
    "email": email,
    "phone": phone,
    "account_type": accountType,
    "role": role,
    "needs_account_type": needsAccountType,
    "is_phone_verified": isPhoneVerified,
    "created_at": "2026-09-05T10:00:00.000000",
  };
}

/// A student rather than a teacher — `account_type` 1.
Map<String, dynamic> studentUserJson({int id = 2}) => userJson(
      id: id,
      fullName: "Aarav Sharma",
      email: "aarav@example.com",
      accountType: 1,
      role: "student",
    );

/// What Google and phone sign-ins come back as: no role yet, so the app must
/// route to GB_CompleteProfile.
Map<String, dynamic> needsRoleUserJson({int id = 3}) => userJson(
      id: id,
      fullName: "GrowBuddy User",
      email: null,
      phone: "+919000000001",
      accountType: null,
      role: null,
      needsAccountType: true,
      isPhoneVerified: true,
    );

/// A `TokenResponse` wrapping [user].
Map<String, dynamic> tokenJson({
  String accessToken = kTestToken,
  bool isNewUser = false,
  Map<String, dynamic>? user,
}) {
  return {
    "access_token": accessToken,
    "token_type": "bearer",
    "is_new_user": isNewUser,
    "user": user ?? userJson(),
  };
}

/// The backend's universal error shape. Every failure is `{"detail": "..."}`,
/// and the app shows that string to the user verbatim.
Map<String, dynamic> detailJson(String message) => {"detail": message};
