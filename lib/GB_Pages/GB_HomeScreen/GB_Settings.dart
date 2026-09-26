import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The settings screen reached from the profile menu, and the only place in the
/// app that offers a logout.
///
/// Sign-out sits here rather than in the profile menu on purpose: the menu is a
/// two-item popup under a 24px icon, where a mis-aimed tap used to end the
/// session outright. Reaching it now takes a deliberate trip into Settings, and
/// `gConfirmAndSignOut` asks once more before anything happens.
///
/// Everything above it is still to be designed. Unlike the home screens this
/// one keeps its back arrow, since it is pushed on top of the dashboard rather
/// than replacing it.
class GB_Settings extends StatelessWidget {
  const GB_Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: AppBar(
        backgroundColor: kPrimaryColor2,
        surfaceTintColor: kPrimaryColor2,
        elevation: 0.0,
        centerTitle: true,
        title: const GB_AppBarText(
          appBarText: "Settings",
          appBarFontWeight: FontWeight.w500,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Takes the space the real settings will eventually fill, and keeps
            // the logout pinned to the bottom of the screen in the meantime
            // rather than floating directly under the app bar.
            const Expanded(child: _GB_SettingsPlaceholder()),
            const Divider(
              height: 1.0,
              thickness: 1.0,
              color: kHomeCardBorderColor,
            ),
            _buildLogoutTile(context),
            const SizedBox(height: 12.0),
          ],
        ),
      ),
    );
  }

  /// The logout row.
  ///
  /// Drawn in the error colour because it is the one destructive thing on the
  /// screen, and separated from the body above by a rule so it cannot be read
  /// as the last of a list of settings.
  Widget _buildLogoutTile(BuildContext context) {
    final Color danger = Theme.of(context).colorScheme.error;

    return ListTile(
      onTap: () => gConfirmAndSignOut(context),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: kHomeHorizontalPadding,
        vertical: 4.0,
      ),
      leading: Icon(Icons.logout, color: danger),
      title: Text(
        "Logout",
        style: TextStyle(
          fontSize: kHomeCardTitleTextSize,
          fontWeight: FontWeight.w500,
          color: danger,
        ),
      ),
      subtitle: const Text(
        "Sign out on this device",
        style: TextStyle(
          fontSize: kClassSubtitleTextSize,
          color: kHomeSubtitleTextColor,
        ),
      ),
    );
  }
}

/// Stands in for the settings themselves, which are not designed yet.
class _GB_SettingsPlaceholder extends StatelessWidget {
  const _GB_SettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.settings_outlined,
              size: 64.0,
              color: kHomeIconColor,
            ),
            SizedBox(height: 16.0),
            GB_H1HeadingText(
              inputText: "Settings",
              inputTextAlign: TextAlign.center,
            ),
            SizedBox(height: 8.0),
            GB_H2HeadingText(
              inputText: "Nothing to configure here yet.",
              inputTextAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
