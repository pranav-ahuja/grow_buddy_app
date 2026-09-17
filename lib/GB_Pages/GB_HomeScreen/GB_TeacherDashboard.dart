import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeDashboard.dart';

/// The teacher's home screen.
///
/// Until 2026-09-17 this file *was* the dashboard — the full screen from the
/// Figma frame `360-39838`. That screen belongs to the principal now
/// ([GB_PrincipalDashboard]); the shared body moved to [GB_HomeDashboard] and
/// both roles are configurations of it.
///
/// What a teacher gets: their own classes, which they may add to and delete
/// from, the register-student action, and a three-tab bar.
///
/// What a teacher does **not** get is the **Fee** tab. Fee status is the
/// principal's, so it is absent rather than present and refusing — a tab whose
/// only job is to say no is worse than one that was never offered. Attendance
/// and Message stay, because those are things a teacher will do.
///
/// A thin wrapper rather than a `GB_HomeDashboard(permissions: ...)` at the
/// call site: the router names a screen, the tests find a type, and the reason
/// the teacher's differs from the principal's lives in one readable place.
class GB_TeacherDashboard extends StatelessWidget {
  const GB_TeacherDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const GB_HomeDashboard(
      permissions: GB_DashboardPermissions.teacher,
    );
  }
}
