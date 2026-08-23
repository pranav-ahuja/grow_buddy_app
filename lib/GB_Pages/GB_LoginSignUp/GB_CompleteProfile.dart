import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_Dashboard.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// Placeholder the backend assigns to phone sign-ups, which arrive with no real
/// name. Treated as "no name yet" so the field starts empty rather than asking
/// the user to delete it.
const String _kPlaceholderName = "GrowBuddy User";

/// Collects the full name and teacher/student choice that Google and phone
/// sign-ins can't supply, then `PATCH /me`.
///
/// Reached from `gRouteAfterAuth` whenever `user.needsAccountType` is true.
/// [isNewUser] only picks the wording — routing here is never decided by it,
/// because someone who abandons this screen stops being "new" on their next
/// login while still having no role.
class GB_CompleteProfile extends StatefulWidget {
  const GB_CompleteProfile({super.key, required this.isNewUser});

  final bool isNewUser;

  @override
  State<GB_CompleteProfile> createState() => _GB_CompleteProfileState();
}

class _GB_CompleteProfileState extends State<GB_CompleteProfile> {
  late final TextEditingController _fullNameController;

  String fullName = "";

  // Null until the user actually picks one, so nobody is silently registered as
  // a teacher just because that constant happens to be 0.
  int? accountType;

  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final String existingName = gCurrentUser?.fullName ?? "";
    fullName = existingName == _kPlaceholderName ? "" : existingName;
    _fullNameController = TextEditingController(text: fullName);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Leaves this screen by signing out.
  ///
  /// Popping is not an option: the auth stack was cleared on the way in, and by
  /// this point the account already exists on the backend — a phone OTP or a
  /// Google sign-in creates it before we ever get here. So "go back and use a
  /// different number" can only mean ending this session.
  ///
  /// Confirmed first because the button looks like an ordinary back arrow, and
  /// signing out is more than the user is likely expecting from it.
  Future<void> _confirmLeave() async {
    if (isSubmitting) return;

    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Use a different account?"),
        content: const Text(
          "You'll be signed out and taken back to the login screen. Your "
          "account is saved — you can sign in again with the same number or "
          "Google account at any time.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Stay here"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sign out"),
          ),
        ],
      ),
    );

    if (leave != true || !mounted) return;
    await gSignOut(context);
  }

  Future<void> _save() async {
    if (fullName.trim().isEmpty) {
      _showSnack("Please enter your full name");
      return;
    }
    if (accountType == null) {
      _showSnack("Please choose whether you're a teacher or a student");
      return;
    }

    final String? token = gLoginToken;
    if (token == null) {
      _showSnack("Your session expired. Please sign in again.");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final GB_User user = await GB_AuthApi.updateProfile(
        token: token,
        fullName: fullName.trim(),
        accountType: accountType,
      );

      await gUpdateCurrentUser(user);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const GB_Dashboard()),
        (route) => false,
      );
    } on GB_ApiException catch (error) {
      _showSnack(error.message);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  /// One of the two role choices. Filled in the brand colour when selected.
  Widget _accountTypeOption({
    required String label,
    required IconData icon,
    required int value,
  }) {
    final bool isSelected = accountType == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(15.0),
          onTap:
              isSubmitting ? null : () => setState(() => accountType = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryColor1 : kPrimaryColor2,
              borderRadius: BorderRadius.circular(15.0),
              border: Border.all(
                color: isSelected ? kPrimaryColor1 : Colors.black26,
                width: 2.0,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 32.0,
                  color: isSelected ? kPrimaryColor2 : kPrimaryColor1,
                ),
                const SizedBox(height: 8.0),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? kPrimaryColor2 : kTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    return PopScope(
      // The route stack is empty behind this screen, so an unhandled system
      // back would drop the user out of the app while still signed in — and the
      // session gate would land them right back here on the next launch. Handle
      // it as "sign out" instead, matching the arrow in the app bar.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: kPrimaryColor2,
        appBar: AppBar(
          // Not a real "back" — there is nothing to pop to. It signs out, which is
          // the only way this screen can be left without finishing it. Without it
          // a user who picked the wrong number is stuck for good, because the
          // stored session routes here on every launch.
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: "Use a different account",
            onPressed: isSubmitting ? null : _confirmLeave,
          ),
          title: GB_AppBarText(
            appBarText: widget.isNewUser ? "Welcome!" : "Finish setting up",
            appBarFontWeight: FontWeight.w500,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset("assets/images/who_are_you.png"),
                GB_H1HeadingText(
                  inputText: widget.isNewUser
                      ? "Welcome to Grow Buddy!"
                      : "Finish setting up your account",
                  inputTextAlign: TextAlign.center,
                ),
                const GB_H2HeadingText(
                  inputText:
                      "Tell us your name and how you'll be using Grow Buddy.",
                  inputTextAlign: TextAlign.center,
                ),
                GB_buildTextField(
                  controller: _fullNameController,
                  suffixIcon: Icons.cancel_outlined,
                  iconAction: () {
                    setState(() {
                      _fullNameController.clear();
                      fullName = "";
                    });
                  },
                  textFieldLabel: "Full Name",
                  textFieldOnChanged: (value) {
                    fullName = value;
                  },
                  textFieldKeyboardType: TextInputType.name,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 10.0, bottom: 10.0),
                  child: Text(
                    "I am a...",
                    textAlign: TextAlign.center,
                    style: kH2TextStyle,
                  ),
                ),
                Row(
                  children: [
                    _accountTypeOption(
                      label: "Teacher",
                      icon: Icons.school_outlined,
                      value: accountTypeTeacher,
                    ),
                    _accountTypeOption(
                      label: "Student",
                      icon: Icons.backpack_outlined,
                      value: accountTypeStudent,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30.0),
                  child: Center(
                    child: GB_ElevatedButtonString(
                      screenWidth: screenWidth,
                      horizontalPadding: 0.2,
                      verticalPadding: kElevatedButtonVerticalPadding,
                      elevatedButtonText:
                          isSubmitting ? "Saving..." : "Continue",
                      buttonColor: kPrimaryColor1,
                      elevatedButtonTextColor: kPrimaryColor2,
                      elevatedButtonFontWeight: FontWeight.w500,
                      elevatedButtonTextSize: kElevatedButtonTextSize,
                      onPressed: isSubmitting ? null : _save,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
