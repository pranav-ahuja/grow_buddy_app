import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_StudentDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The landing screen for a signed-in user, and the one thing the auth flows
/// know about — `gRouteAfterAuth` and [GB_SessionGate] both push this.
///
/// It owns no UI of its own: it reads the signed-in user's role and shows the
/// matching dashboard. Keeping the choice here means the auth code never has to
/// care which role it just signed in, and a new role is one branch away.
///
/// A teacher gets [GB_TeacherDashboard] — the home screen from the Figma frame
/// `360-39838`, with the events carousel, class list, register-new-student
/// button, and bottom navigation bar. A student gets [GB_StudentDashboard],
/// which is still a placeholder because that design does not exist yet. So a
/// student account seeing "Your dashboard is on its way" is this branch working
/// as intended, not a missing screen.
class GB_Dashboard extends StatelessWidget {
  const GB_Dashboard({super.key});

  /// The backend sends `role` as "teacher"/"student", but it stays null until
  /// an account type is chosen, so [GB_User.accountType] is the fallback.
  ///
  /// A user with neither should have been sent to `GB_CompleteProfile` before
  /// reaching here; if one slips through, the student screen is the safer
  /// landing of the two — it shows nothing a teacher-only account could act on.
  bool _isTeacher(GB_User? user) {
    if (user == null) return false;

    final String? role = user.role?.toLowerCase();
    if (role != null && role.isNotEmpty) return role == "teacher";

    return user.accountType == accountTypeTeacher;
  }

  @override
  Widget build(BuildContext context) {
    return _isTeacher(gCurrentUser)
        ? const GB_TeacherDashboard()
        : const GB_StudentDashboard();
  }
}
