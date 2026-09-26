import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_NotificationStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_ProfilePhotoStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_SessionStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

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

/// Which of the three roles the signed-in account is, as an account type.
///
/// `role` is the answer whenever the backend has one; it stays null until an
/// account type is chosen, so [GB_User.accountType] is the fallback — the same
/// answer by another name. Null means neither, which is an account that should
/// have been sent to `GB_CompleteProfile` before it got anywhere.
///
/// **One implementation, on purpose.** Three screens now branch on the role —
/// the dashboard router, the home screen's powers, and the class screen's —
/// and three copies of this mapping is how one of them ends up disagreeing
/// about who the principal is. Note it answers from the *cached* user, so it
/// is a claim about what this device was last told, not a permission: the
/// server decides every one of these questions again on its own.
int? gCurrentAccountType() {
  final GB_User? user = gCurrentUser;
  if (user == null) return null;

  return switch (user.role?.toLowerCase()) {
    "teacher" => accountTypeTeacher,
    "student" => accountTypeStudent,
    "principal" => accountTypePrincipal,
    _ => user.accountType,
  };
}

/// True for the school's admin.
///
/// What it gates in the UI is *offering* an action, never allowing one. A
/// teacher who somehow reached the principal's button still gets a 403, and a
/// principal who somehow did not see it has lost nothing they cannot reach
/// another way.
bool gIsPrincipal() => gCurrentAccountType() == accountTypePrincipal;

/// True for a teacher — the role that raises approval requests rather than
/// making changes outright.
bool gIsTeacher() => gCurrentAccountType() == accountTypeTeacher;

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
///
/// The profile picture is only forgotten, not deleted: it is stored against
/// the user's own id, so the next account gets a blank avatar while the
/// original owner gets theirs back on their next sign-in.
Future<void> gClearSession() async {
  gLoginToken = null;
  gCurrentUser = null;
  GB_ClassStore.clear();
  GB_StudentStore.clear();
  // The bell too. A notification is addressed to one account, and the next
  // person to sign in on this phone must not find the last one's approval
  // queue sitting behind the icon.
  GB_NotificationStore.clear();
  GB_ProfilePhotoStore.forget();
  await GB_SessionStore.clear();
}
