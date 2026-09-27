import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_EditProfileSheet.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Services/GB_ProfilePhotoStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:image_picker/image_picker.dart';

/// What the photo chooser came back with.
///
/// The same three answers the register-student sheet offers, and an enum for
/// the same reason: "remove the picture I already set" is a third outcome that
/// [ImageSource] has no value for.
enum _PhotoAction { camera, gallery, remove }

/// Who is signed in on this device — the screen behind the "Profile" item in
/// the home bar's profile menu.
///
/// Everything shown here comes from [gCurrentUser], which `GB_SessionGate`
/// refreshes from `GET /auth/me` on every launch, so the screen draws itself
/// with no request of its own and works offline from the cached user.
///
/// **Edit** opens [GB_EditProfileSheet], the only thing here that talks to the
/// server. The plan recorded in docs/PROJECT.md was for it to reuse
/// `GB_CompleteProfile` instead; that screen turned out to be the wrong shape
/// for an edit — it hides a contact that is already set, and its back arrow
/// signs out — and the sheet says why in full.
///
/// **The role is shown but not editable**, unlike the two rows above it. It is
/// what the whole app branches on rather than a detail its owner corrects, so
/// it is not among the fields the sheet offers.
///
/// The user id is deliberately **not** shown. It is a database key — the app
/// needs it, the teacher does not, and putting `U_000001` on a profile invites
/// it into a support conversation as though it meant something to them.
///
/// Pushed on top of the dashboard rather than replacing it, so it keeps its
/// back arrow.
class GB_Profile extends StatefulWidget {
  const GB_Profile({super.key});

  @override
  State<GB_Profile> createState() => _GB_ProfileState();
}

class _GB_ProfileState extends State<GB_Profile> {
  /// Guards against a second picker being opened while one is already up — the
  /// avatar is a large tap target and easy to double-tap.
  bool _isPickingPhoto = false;

  @override
  void initState() {
    super.initState();
    final GB_User? user = gCurrentUser;
    if (user != null) GB_ProfilePhotoStore.load(user.userId);
  }

  /// The user's initials for the avatar, e.g. "Pranav Ahuja" -> "PA".
  ///
  /// Falls back to a person icon rather than to a letter when there is no
  /// usable name: a lone "G" from the "GrowBuddy User" placeholder would read
  /// as a real initial.
  static String? _initials(String fullName) {
    final List<String> words = fullName
        .trim()
        .split(RegExp(r"\s+"))
        .where((String word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;
    if (words.length == 1) return words.first[0].toUpperCase();
    return "${words.first[0]}${words.last[0]}".toUpperCase();
  }

  /// "teacher" -> "Teacher". The backend stores the role lower-case; this is
  /// the only place it is shown to a person.
  static String _roleLabel(GB_User user) {
    final String? role = user.role;
    if (role != null && role.isNotEmpty) {
      return role[0].toUpperCase() + role.substring(1);
    }
    // Null role means the profile was never completed — the account type is
    // the same answer by another name, and null there too means neither.
    return gAccountTypeLabel(user.accountType) ?? "Role not set";
  }

  /// Offers camera, gallery, and — only when there is one to remove — a way
  /// back to initials.
  ///
  /// Mirrors `_pickPhoto` on the register-student sheet rather than sharing it:
  /// that one holds an unsaved form field, this one writes straight through to
  /// the store, so the two have the same shape but different endings.
  Future<void> _changePhoto(GB_User user) async {
    if (_isPickingPhoto) return;
    _isPickingPhoto = true;

    try {
      final bool hasPhoto = GB_ProfilePhotoStore.photoPath.value != null;

      final _PhotoAction? action = await showModalBottomSheet<_PhotoAction>(
        context: context,
        backgroundColor: kPrimaryColor2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(kClassPanelRadius),
          ),
        ),
        builder: (BuildContext context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: kHomeAccentColor,
                ),
                title: const Text("Take a photo"),
                onTap: () => Navigator.of(context).pop(_PhotoAction.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: kHomeAccentColor,
                ),
                title: const Text("Choose from gallery"),
                onTap: () => Navigator.of(context).pop(_PhotoAction.gallery),
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: kHomeSubtitleTextColor,
                  ),
                  title: const Text("Remove photo"),
                  onTap: () => Navigator.of(context).pop(_PhotoAction.remove),
                ),
            ],
          ),
        ),
      );

      // Null is a dismissal, which is not the same as choosing "Remove photo".
      if (action == null || !mounted) return;

      if (action == _PhotoAction.remove) {
        await GB_ProfilePhotoStore.clearFor(user.userId);
        if (!mounted) return;
        gShowSnack(context, "Profile picture removed");
        return;
      }

      // Downscaled on the way in: the picture is drawn at 88pt, and a
      // full-resolution camera capture would be megabytes held for a thumbnail.
      final XFile? picked = await ImagePicker().pickImage(
        source: action == _PhotoAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 800.0,
        maxHeight: 800.0,
        imageQuality: 85,
      );

      if (picked == null || !mounted) return;

      await GB_ProfilePhotoStore.save(userId: user.userId, path: picked.path);
      if (!mounted) return;
      gShowSnack(context, "Profile picture updated");
    } on PlatformException {
      // Thrown when the picker is unavailable or permission was refused. The
      // picture is optional, so this is worth saying once and no more.
      if (!mounted) return;
      gShowSnack(context, "Couldn't open the photo picker");
    } finally {
      _isPickingPhoto = false;
    }
  }

  /// Opens the edit sheet and redraws this screen with what came back.
  ///
  /// The sheet has already written the new user to [gCurrentUser] and to secure
  /// storage by the time it returns, so this only has to rebuild — and it
  /// returns null when nothing was saved, which is the common case of a sheet
  /// swiped away.
  Future<void> _editDetails(GB_User user) async {
    final GB_User? updated = await GB_EditProfileSheet.show(context, user);
    if (updated == null || !mounted) return;
    setState(() {});
    gShowSnack(context, "Your details are updated");
  }

  @override
  Widget build(BuildContext context) {
    final GB_User? user = gCurrentUser;

    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: AppBar(
        backgroundColor: kPrimaryColor2,
        surfaceTintColor: kPrimaryColor2,
        elevation: 0.0,
        centerTitle: true,
        title: const GB_AppBarText(
          appBarText: "Profile",
          appBarFontWeight: FontWeight.w500,
        ),
        actions: [
          // Absent rather than disabled when there is no session: there is
          // nothing to edit, and a greyed-out button would invite a tap that
          // could only fail.
          if (user != null)
            TextButton(
              onPressed: () => _editDetails(user),
              child: const Text(
                "Edit",
                style: TextStyle(
                  fontSize: kEventSubtitleTextSize,
                  fontWeight: FontWeight.w500,
                  color: kHomeAccentColor,
                ),
              ),
            ),
        ],
      ),
      // Null only if the session was cleared while this screen was open —
      // gSignOut replaces the whole stack, so in practice it is unreachable.
      // Saying so beats a screen of blank rows.
      body: user == null ? _buildSignedOut() : _buildProfile(user),
    );
  }

  Widget _buildSignedOut() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: GB_H2HeadingText(
          inputText: "You're not signed in.",
          inputTextAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildProfile(GB_User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        kHomeHorizontalPadding,
        8.0,
        kHomeHorizontalPadding,
        32.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(user),
          const SizedBox(height: 28.0),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Account details",
              style: TextStyle(
                fontSize: kClassSectionHeaderSize,
                fontWeight: FontWeight.w500,
                color: kHomeTitleTextColor,
              ),
            ),
          ),
          const SizedBox(height: 12.0),
          _buildDetailsCard(user),
        ],
      ),
    );
  }

  /// The avatar, name, and role — the part that answers "whose account is
  /// this?" without the reader having to parse a table.
  Widget _buildHeader(GB_User user) {
    return Column(
      children: [
        _buildAvatar(user),
        const SizedBox(height: 14.0),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: kHomeCardTitleTextSize,
            fontWeight: FontWeight.w500,
            color: kHomeTitleTextColor,
          ),
        ),
        const SizedBox(height: 8.0),
        // A pill rather than another line of text: the role is what the whole
        // app branches on, so it should not read as one more detail among six.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kPillButtonHorizontalPadding,
            vertical: 6.0,
          ),
          decoration: BoxDecoration(
            color: kClassTileGreenFill,
            border: Border.all(color: kClassTileGreenBorder),
            borderRadius: BorderRadius.circular(kPillButtonRadius),
          ),
          child: Text(
            _roleLabel(user),
            style: const TextStyle(
              fontSize: kPillButtonTextSize,
              fontWeight: FontWeight.w500,
              color: kHomeAccentColor,
            ),
          ),
        ),
      ],
    );
  }

  /// The profile picture, with the camera badge that changes it.
  ///
  /// The whole circle is the tap target, not just the badge: the badge is a
  /// 28pt affordance saying the picture is changeable, and making it the only
  /// way in would put the real action below the recommended minimum.
  Widget _buildAvatar(GB_User user) {
    return ValueListenableBuilder<String?>(
      valueListenable: GB_ProfilePhotoStore.photoPath,
      builder: (BuildContext context, String? photoPath, _) {
        return Semantics(
          button: true,
          // One node of its own, with the initials inside it excluded. Left to
          // merge, a screen reader would announce the avatar as its own
          // initials ("PA") and bury what tapping it actually does — and the
          // name is read out in full on the line below regardless.
          container: true,
          excludeSemantics: true,
          label: photoPath == null
              ? "Add a profile picture"
              : "Change your profile picture",
          child: GestureDetector(
            onTap: () => _changePhoto(user),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 44.0,
                  backgroundColor: kClassTileGreenFill,
                  // A File rather than an asset: the path came from the
                  // device's own picker.
                  foregroundImage: photoPath == null
                      ? null
                      : FileImage(File(photoPath)),
                  // Reached when the file has gone since it was picked. The
                  // initials underneath simply show through, so there is
                  // nothing to rebuild — but the stored path is now dead, so
                  // forget it rather than retry every rebuild.
                  //
                  // Null alongside a null image, not merely pointless:
                  // CircleAvatar asserts that a handler without an image is a
                  // mistake, which would throw on every avatar with no picture.
                  onForegroundImageError: photoPath == null
                      ? null
                      : (Object error, StackTrace? stack) {
                          GB_ProfilePhotoStore.clearFor(user.userId);
                        },
                  child: _buildAvatarFallback(user),
                ),
                // Ringed in the page colour so the badge reads as sitting on
                // top of the picture rather than punched out of it.
                Container(
                  padding: const EdgeInsets.all(5.0),
                  decoration: const BoxDecoration(
                    color: kHomeAccentColor,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: kPrimaryColor2, width: 2.0),
                    ),
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    size: 16.0,
                    color: kPrimaryColor2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// What the avatar shows with no picture set: the user's initials, or a
  /// person icon when the name cannot produce any.
  Widget _buildAvatarFallback(GB_User user) {
    final String? initials = _initials(user.fullName);

    if (initials == null) {
      return const Icon(
        Icons.person_outline,
        size: 44.0,
        color: kHomeAccentColor,
      );
    }

    return Text(
      initials,
      style: const TextStyle(
        fontSize: 32.0,
        fontWeight: FontWeight.w500,
        color: kHomeAccentColor,
      ),
    );
  }

  Widget _buildDetailsCard(GB_User user) {
    return Container(
      decoration: BoxDecoration(
        color: kPrimaryColor2,
        border: Border.all(color: kHomeCardBorderColor),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kClassTilePadding,
        vertical: 4.0,
      ),
      child: Column(
        children: [
          // No user id row: it is a database key, and the name is already the
          // headline above, so the card carries only what a teacher would
          // actually want to check or correct.
          _GB_ProfileDetailRow(
            icon: Icons.mail_outline,
            label: "Email",
            value: user.email,
          ),
          _GB_ProfileDetailRow(
            icon: Icons.phone_outlined,
            label: "Phone",
            value: user.phone,
            // Only the OTP flow can set this, so an unverified number is a
            // number typed into the profile form and never proven.
            trailing: user.phone != null && user.isPhoneVerified
                ? const Icon(
                    Icons.verified_outlined,
                    size: 18.0,
                    color: kHomeAccentColor,
                  )
                : null,
          ),
          _GB_ProfileDetailRow(
            icon: Icons.school_outlined,
            label: "Role",
            value: user.role,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

/// One labelled line of the account-details card.
///
/// A null [value] draws "Not added yet" in the muted colour instead of an
/// empty gap, because every user is meant to end up with both an email and a
/// phone number — a blank row would look like a rendering bug rather than
/// something still to fill in.
class _GB_ProfileDetailRow extends StatelessWidget {
  const _GB_ProfileDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;

  /// Suppresses the divider under the final row, which would otherwise draw a
  /// line along the inside of the card's own border.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final String? text = value;
    final bool isMissing = text == null || text.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: Row(
            children: [
              Icon(icon, size: 20.0, color: kHomeIconColor),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: kClassSubtitleTextSize,
                        color: kHomeSubtitleTextColor,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      isMissing ? "Not added yet" : text,
                      style: TextStyle(
                        fontSize: kEventSubtitleTextSize,
                        color: isMissing
                            ? kHomeSubtitleTextColor
                            : kHomeTitleTextColor,
                        fontStyle:
                            isMissing ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1.0, thickness: 1.0, color: kHomeCardBorderColor),
      ],
    );
  }
}
