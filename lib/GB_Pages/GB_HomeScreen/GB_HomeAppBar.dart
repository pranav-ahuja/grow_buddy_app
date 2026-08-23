import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Settings.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// What the profile menu offers. An enum rather than raw strings so a typo in
/// one of the two places becomes a compile error instead of a menu item that
/// silently does nothing.
enum GB_ProfileMenuAction { settings, logout }

/// The top bar shared by every home screen: centred "Grow Buddy" title with a
/// profile button on the right.
///
/// No hamburger on the left — the mockup's left-hand menu is covered by the
/// bottom navigation bar, so `automaticallyImplyLeading` stays off and nothing
/// takes its place.
class GB_HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GB_HomeAppBar({super.key, this.title = "Grow Buddy"});

  final String title;

  /// The toolbar plus the one-pixel rule added as [AppBar.bottom]; Scaffold
  /// lays the body out against this, so leaving the rule out would let the
  /// first card slide a pixel under the bar.
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1.0);

  void _handleAction(BuildContext context, GB_ProfileMenuAction action) {
    switch (action) {
      case GB_ProfileMenuAction.settings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GB_Settings()),
        );
      case GB_ProfileMenuAction.logout:
        // gSignOut clears the token, signs out of Google, and lands on the
        // login page — the whole logout contract lives there, not here.
        gSignOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: kPrimaryColor2,
      surfaceTintColor: kPrimaryColor2,
      elevation: 0.0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontSize: kHomeAppBarTextSize,
        height: 28.0 / kHomeAppBarTextSize,
        fontWeight: FontWeight.w500,
        color: kHomeTitleTextColor,
      ),
      // The design underlines the bar with a translucent gold hairline rather
      // than a shadow, so elevation stays at 0 and the rule is drawn here.
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1.0),
        child: Divider(
          height: 1.0,
          thickness: 1.0,
          color: kHomeAppBarBorderColor,
        ),
      ),
      title: GB_AppBarText(
        appBarText: title,
        appBarFontWeight: FontWeight.w500,
      ),
      actions: [
        PopupMenuButton<GB_ProfileMenuAction>(
          icon: const Icon(
            Icons.account_circle_outlined,
            color: kHomeIconColor,
          ),
          iconSize: 24.0,
          // The menu surface, not the icon — that is set on the Icon above.
          color: kPrimaryColor2,
          tooltip: "Profile",
          position: PopupMenuPosition.under,
          onSelected: (action) => _handleAction(context, action),
          itemBuilder: (context) => const [
            PopupMenuItem<GB_ProfileMenuAction>(
              value: GB_ProfileMenuAction.settings,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.settings_outlined, color: kHomeIconColor),
                title: Text("Settings"),
              ),
            ),
            PopupMenuItem<GB_ProfileMenuAction>(
              value: GB_ProfileMenuAction.logout,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, color: kHomeIconColor),
                title: Text("Logout"),
              ),
            ),
          ],
        ),
        const SizedBox(width: 6.0),
      ],
    );
  }
}
