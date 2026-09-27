import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_NotificationStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_NotificationsScreen.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Profile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Settings.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApprovalModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// What the profile menu offers. An enum rather than raw strings so a typo in
/// one of the two places becomes a compile error instead of a menu item that
/// silently does nothing.
///
/// Logout is deliberately **not** here. The icon is a profile icon, so the menu
/// under it holds the two places a profile leads to; signing out lives at the
/// bottom of [GB_Settings], behind a confirmation. Both items here are harmless
/// to tap by mistake, which the menu's previous second entry was not — one
/// stray tap ended the session outright, with no way back but logging in again.
enum GB_ProfileMenuAction { profile, settings }

/// The top bar shared by every home screen: centred "Grow Buddy" title, with
/// the notification bell and the profile button on the right.
///
/// No hamburger on the left — the mockup's left-hand menu is covered by the
/// bottom navigation bar, so `automaticallyImplyLeading` stays off and nothing
/// takes its place.
///
/// **The bell is where approvals arrive.** It is here rather than in the
/// bottom bar because the bar's four destinations are the school's sections
/// and three of them are still unbuilt; adding a fifth to carry a queue would
/// have reshuffled a row of tabs that nothing else is ready to change. The
/// badge is the server's unread count, not one this bar keeps — see
/// [GB_NotificationStore].
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
      case GB_ProfileMenuAction.profile:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GB_Profile()),
        );
      case GB_ProfileMenuAction.settings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GB_Settings()),
        );
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
        _buildBell(context),
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
              value: GB_ProfileMenuAction.profile,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.account_circle_outlined,
                  color: kHomeIconColor,
                ),
                title: Text("Profile"),
              ),
            ),
            PopupMenuItem<GB_ProfileMenuAction>(
              value: GB_ProfileMenuAction.settings,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.settings_outlined, color: kHomeIconColor),
                title: Text("Settings"),
              ),
            ),
          ],
        ),
        const SizedBox(width: 6.0),
      ],
    );
  }

  /// The bell, with the unread count on it.
  ///
  /// Listens to the store rather than taking a number, so approving something
  /// on the notifications screen clears the badge behind it without the
  /// dashboard being told to rebuild.
  ///
  /// The count shown is **unread notices**, not the principal's queue depth.
  /// They are usually the same number and deliberately not the same thing: a
  /// principal who has read a request but not answered it should not keep
  /// being nagged by a badge, and the request is still sitting at the top of
  /// the screen the bell opens.
  Widget _buildBell(BuildContext context) {
    return ValueListenableBuilder<GB_NotificationFeed>(
      valueListenable: GB_NotificationStore.feed,
      builder: (BuildContext context, GB_NotificationFeed feed, _) {
        return IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GB_NotificationsScreen(),
            ),
          ),
          iconSize: 24.0,
          tooltip: feed.unread == 0
              ? "Notifications"
              : "Notifications (${feed.unread} unread)",
          icon: Badge(
            // Drawn only when there is something to say. A badge showing "0"
            // is a badge that has stopped meaning anything.
            isLabelVisible: feed.unread > 0,
            // Capped, because the bar has room for two digits and a bell
            // reading "137" is not more informative than one reading "9+".
            label: Text(feed.unread > 9 ? "9+" : "${feed.unread}"),
            backgroundColor: kHomeAccentColor,
            textColor: kPrimaryColor2,
            child: const Icon(
              Icons.notifications_none,
              color: kHomeIconColor,
            ),
          ),
        );
      },
    );
  }
}
