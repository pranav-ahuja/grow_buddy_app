import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeDashboard.dart';

/// The principal's home screen — the school, rather than one classroom.
///
/// This is the dashboard from the Figma frame `360-39838`, the one that was
/// built first and lived on `GB_TeacherDashboard` until 2026-09-17. It is the
/// principal's now, by decision: it is a whole-school view, and the person it
/// was really describing is the admin.
///
/// The class list here spans **every teacher**, which is why tiles name their
/// owner — two teachers each having a "Nursery" is normal and allowed, so
/// without the name that list would be two identical rows. The scoping is the
/// server's: the same `GET /classes` returns one teacher's classes to a
/// teacher and all of them to a principal, so this screen does no filtering it
/// could get wrong.
///
/// What is deliberately absent: **no "Add a class" tile and no delete.** A
/// class belongs to the teacher who owns it, and the backend refuses a
/// principal's `POST /classes` for the same reason. The principal's part is to
/// assign teachers to classes — a different act, on a class that already
/// exists, and one that arrives in a later phase.
///
/// What is here and not on the teacher's: the **Fee** tab.
///
/// Still to come: assigning teachers to classes, assigning and approving
/// subjects, and the fee, salary and funds views. The four-tab bar and the
/// register-student action work today.
class GB_PrincipalDashboard extends StatelessWidget {
  const GB_PrincipalDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const GB_HomeDashboard(
      permissions: GB_DashboardPermissions.principal,
    );
  }
}
