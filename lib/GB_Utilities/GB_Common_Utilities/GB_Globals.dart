import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';

/// JWT returned by the backend on sign-up, login, or OTP verification.
///
/// Mirrored to [GB_SessionStore] so the session survives the app being killed;
/// these globals are the hot copy that the UI reads synchronously.
String? gLoginToken;

/// The signed-in user, populated alongside [gLoginToken].
GB_User? gCurrentUser;

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

Future<void> gClearSession() async {
  gLoginToken = null;
  gCurrentUser = null;
  await GB_SessionStore.clear();
}
