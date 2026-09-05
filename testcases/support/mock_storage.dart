/// Swaps `flutter_secure_storage` for an in-memory map.
///
/// Uses the test double the package itself ships rather than mocking the
/// MethodChannel by hand: it is the supported seam, and it cannot drift out of
/// step with the plugin's own call shapes.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';

/// Keys GB_SessionStore writes under. Duplicated here deliberately: they are
/// private to the store, and a test asserting on them is asserting on the
/// on-disk contract, which should not change silently.
const String kTokenKey = "gb_auth_token";
const String kUserKey = "gb_auth_user";

/// Installs the in-memory platform and returns its backing map, so a test can
/// both seed it and assert on what the app wrote.
Map<String, String> installMockSecureStorage([Map<String, String>? seed]) {
  final Map<String, String> data = <String, String>{...?seed};
  FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(data);
  return data;
}

/// Seeds storage as though [user] were already signed in, for testing launch
/// paths that resume a session.
Map<String, String> installStoredSession({
  String token = "stored.jwt.token",
  Map<String, dynamic>? user,
}) {
  return installMockSecureStorage({
    kTokenKey: token,
    kUserKey: jsonEncode(user ?? GB_User.fromJson(_defaultUser).toJson()),
  });
}

final Map<String, dynamic> _defaultUser = {
  "id": 1,
  "full_name": "Pranav Ahuja",
  "email": "pranav@example.com",
  "phone": null,
  "account_type": 0,
  "role": "teacher",
  "needs_account_type": false,
  "is_phone_verified": false,
};
