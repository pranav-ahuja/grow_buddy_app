import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';

/// JWT returned by the backend on sign-up, login, or OTP verification.
///
/// Mirrored to [GB_SessionStore] so the session survives the app being killed;
/// these globals are the hot copy that the UI reads synchronously.
String? gLoginToken;

/// The signed-in user, populated alongside [gLoginToken].
GB_User? gCurrentUser;

/// [gLoginToken], for a call that is meaningless signed out — every request
/// for the teacher's own classes and students.
///
/// Throws the same exception the network layer does, so callers already
/// catching [GB_ApiException] show this like any other failure.
String gRequireToken() {
  final String? token = gLoginToken;
  if (token == null) {
    throw GB_ApiException("You've been signed out. Please log in again.");
  }
  return token;
}

/// Sets the session and writes it to disk.
///
/// The globals are assigned before the await so a caller that navigates
/// immediately — every auth screen does — finds them already populated. The
/// returned future only matters if you need the write itself to have landed.
Future<void> gSetSession(GB_AuthResult result) async {
  gLoginToken = result.token;
  gCurrentUser = result.user;
  await GB_SessionStore.save(token: result.token, user: result.user);
}

/// Restores a session read back from storage at launch.
void gRestoreSession({required String token, required GB_User user}) {
  gLoginToken = token;
  gCurrentUser = user;
}

/// Replaces the cached user without touching the token — for `PATCH /me`, which
/// returns a fresh user but no new token.
Future<void> gUpdateCurrentUser(GB_User user) async {
  gCurrentUser = user;
  await GB_SessionStore.saveUser(user);
}

/// Ends the session on this device.
///
/// Also empties the class and student stores. They are a copy of one
/// account's data, and without this, the next person to sign in on the same
/// device would see the previous teacher's classes until the first load
/// replaced them.
Future<void> gClearSession() async {
  gLoginToken = null;
  gCurrentUser = null;
  GB_ClassStore.clear();
  GB_StudentStore.clear();
  await GB_SessionStore.clear();
}
