import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_PrincipalDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_StudentDashboard.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_TeacherDashboard.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The landing screen for a signed-in user, and the one thing the auth flows
/// know about — `gRouteAfterAuth` and [GB_SessionGate] both push this.
///
/// It owns no UI of its own: it reads the signed-in user's role and shows the
/// matching dashboard. Keeping the choice here means the auth code never has to
/// care which role it just signed in, and a new role is one branch away.
///
/// The principal gets [GB_PrincipalDashboard] — the home screen from the Figma
/// frame `360-39838`, which is a whole-school view and belongs to the admin.
/// A teacher gets [GB_TeacherDashboard]: the same body, narrowed to their own
/// classes and without the Fee tab. Both are configurations of
/// [GB_HomeDashboard]; the differences between them live there.
///
/// A student gets [GB_StudentDashboard], which is still a placeholder because
/// that design does not exist yet. So a student account seeing "Your dashboard
/// is on its way" is this branch working as intended, not a missing screen.
class GB_Dashboard extends StatelessWidget {
  const GB_Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // [gCurrentAccountType] is the one place this mapping lives. It used to be
    // written out here, and again wherever else a screen needed to know the
    // role, which is how two of them end up disagreeing about who the
    // principal is.
    return switch (gCurrentAccountType()) {
      accountTypeTeacher => const GB_TeacherDashboard(),
      accountTypePrincipal => const GB_PrincipalDashboard(),
      // Everything else, including a user with no role at all, gets the
      // student screen: it is the safer landing of the three, showing nothing
      // a teacher-only or admin-only account could act on.
      _ => const GB_StudentDashboard(),
    };
  }
}
