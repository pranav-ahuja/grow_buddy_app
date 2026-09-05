/// The session is a bearer credential: whatever holds it *is* the user until it
/// expires. These cover both the in-memory globals the UI reads synchronously
/// and the encrypted copy that survives the app being killed.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

import '../support/fixtures.dart';
import '../support/mock_storage.dart';

void main() {
  late Map<String, String> storage;

  setUp(() {
    storage = installMockSecureStorage();
    gLoginToken = null;
    gCurrentUser = null;
  });

  tearDown(() {
    gLoginToken = null;
    gCurrentUser = null;
  });

  group("GB_SessionStore", () {
    test("session_saves_token_and_user | Both land under their own keys",
        () async {
      await GB_SessionStore.save(
        token: "jwt-abc",
        user: GB_User.fromJson(userJson()),
      );

      expect(storage[kTokenKey], "jwt-abc");
      expect(
        (jsonDecode(storage[kUserKey]!) as Map<String, dynamic>)["full_name"],
        "Pranav Ahuja",
      );
    });

    test("session_reads_back | What was written comes back intact", () async {
      await GB_SessionStore.save(
        token: "jwt-abc",
        user: GB_User.fromJson(userJson(phone: "+911234567890")),
      );

      expect(await GB_SessionStore.readToken(), "jwt-abc");
      final GB_User? restored = await GB_SessionStore.readUser();
      expect(restored!.fullName, "Pranav Ahuja");
      expect(restored.phone, "+911234567890");
      expect(restored.role, "teacher");
    });

    test("session_empty_reads_null | A fresh install has no session", () async {
      expect(await GB_SessionStore.readToken(), isNull);
      expect(await GB_SessionStore.readUser(), isNull);
    });

    test("session_survives_corrupt_cache | Bad JSON returns null, not a crash",
        () async {
      // Most likely a cache written by an older build whose shape has since
      // changed. Failing a launch over it would lock the user out; /me refills
      // it anyway.
      installMockSecureStorage({kUserKey: "{not valid json"});

      expect(await GB_SessionStore.readUser(), isNull);
    });

    test("session_save_user_keeps_token | PATCH /me replaces only the user",
        () async {
      // PATCH returns a fresh user but no new token, so rewriting the token
      // would blank it.
      await GB_SessionStore.save(
        token: "jwt-abc",
        user: GB_User.fromJson(userJson()),
      );

      await GB_SessionStore.saveUser(
        GB_User.fromJson(userJson(fullName: "Renamed")),
      );

      expect(await GB_SessionStore.readToken(), "jwt-abc");
      expect((await GB_SessionStore.readUser())!.fullName, "Renamed");
    });

    test("session_clear_removes_everything | Logout leaves nothing behind",
        () async {
      await GB_SessionStore.save(
        token: "jwt-abc",
        user: GB_User.fromJson(userJson()),
      );

      await GB_SessionStore.clear();

      expect(storage[kTokenKey], isNull);
      expect(storage[kUserKey], isNull);
    });
  });

  group("globals", () {
    test("set_session_fills_globals | The UI can read them synchronously",
        () async {
      // Every auth screen navigates immediately after calling this, so the
      // globals must be populated before the future completes.
      final GB_AuthResult result = GB_AuthResult.fromJson(tokenJson());

      final Future<void> pending = gSetSession(result);

      expect(gLoginToken, kTestToken);
      expect(gCurrentUser!.fullName, "Pranav Ahuja");
      await pending;
      expect(storage[kTokenKey], kTestToken);
    });

    test("restore_session_fills_globals | A stored session repopulates them",
        () {
      gRestoreSession(
        token: "stored-jwt",
        user: GB_User.fromJson(userJson()),
      );

      expect(gLoginToken, "stored-jwt");
      expect(gCurrentUser!.role, "teacher");
    });

    test("update_user_keeps_token | Completing a profile does not sign you out",
        () async {
      await gSetSession(GB_AuthResult.fromJson(tokenJson()));

      await gUpdateCurrentUser(
        GB_User.fromJson(userJson(fullName: "Completed", accountType: 1)),
      );

      expect(gLoginToken, kTestToken);
      expect(gCurrentUser!.fullName, "Completed");
      expect(gCurrentUser!.accountType, 1);
    });

    test("clear_session_empties_both | Logout clears memory and disk",
        () async {
      await gSetSession(GB_AuthResult.fromJson(tokenJson()));

      await gClearSession();

      expect(gLoginToken, isNull);
      expect(gCurrentUser, isNull);
      expect(storage[kTokenKey], isNull);
    });
  });
}
