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
/// **The principal is the school's administrator**, and since 2026-09-20 that
/// is what this screen offers. They add classes and delete them, register
/// pupils and remove them, and all four take effect immediately. Where a
/// teacher does any of the same four, it becomes a request that arrives here
/// behind the app bar's bell for the principal to approve or turn down.
///
/// Until that date this screen had no "Add a class" tile and no bin, on the
/// reasoning that a class belongs to the teacher who owns it. The role is an
/// administrator's now and that reasoning no longer holds — but its useful
/// half survives in the schema: a class the principal creates is filed under
/// the teacher they pick, or under **nobody**, and never under the principal.
/// They have no teacher record to own one with.
///
/// Choosing **who teaches a class** is not here either, and deliberately: it
/// is an act on a class that already exists, so it lives on the class screen
/// behind its "Add teacher" button, where several teachers can be picked at
/// once.
///
/// What is here and not on the teacher's: the **Fee** tab.
///
/// Still to come: assigning and approving subjects, and the fee, salary and
/// funds views.
class GB_PrincipalDashboard extends StatelessWidget {
  const GB_PrincipalDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const GB_HomeDashboard(
      permissions: GB_DashboardPermissions.principal,
    );
  }
}
