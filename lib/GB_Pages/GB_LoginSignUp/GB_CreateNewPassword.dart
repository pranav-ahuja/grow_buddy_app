import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';

/// Step 3 of the password reset flow: pick the replacement password.
class GB_CreateNewPassword extends StatefulWidget {
  const GB_CreateNewPassword({super.key, required this.emailID});

  final String emailID;

  @override
  State<GB_CreateNewPassword> createState() => _GB_CreateNewPasswordState();
}

class _GB_CreateNewPasswordState extends State<GB_CreateNewPassword> {
  final TextEditingController _password_controller = TextEditingController();
  final TextEditingController _confirm_password_controller =
      TextEditingController();

  bool passwordVisible = false;
  bool confirmPasswordVisible = false;

  bool isSubmitting = false;

  @override
  void dispose() {
    _password_controller.dispose();
    _confirm_password_controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _changePassword() async {
    final password = _password_controller.text;
    final confirmPassword = _confirm_password_controller.text;

    if (password.isEmpty || confirmPassword.isEmpty) {
      _showSnack("Please enter and re-enter your new password");
      return;
    }
    if (password != confirmPassword) {
      _showSnack("The two passwords do not match");
      return;
    }

    setState(() => isSubmitting = true);
    // TODO(backend): send the new password with the reset token from
    // GB_VerifyEmail, then drop the user back on the login screen.
    try {
      if (!mounted) return;
      _showSnack("Password changed. Please log in.");
      // The reset flow is finished, so clear it off the stack instead of
      // leaving a back button into a spent verification code.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => GB_Login()),
        (route) => route.isFirst,
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: GB_AppBarText(
          appBarText: "Create New Password",
          appBarFontWeight: FontWeight.w500,
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Image.asset(
                  "assets/images/forget_password_3.png",
                  height: 250.0,
                ),
              ),
              GB_H1HeadingText(
                inputText: "Enter new password",
                inputTextAlign: TextAlign.left,
              ),
              GB_H2HeadingText(
                inputText:
                    "Your new password must be different from the previous passwords.",
                inputTextAlign: TextAlign.left,
              ),
              Container(
                margin: EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    GB_buildTextField(
                      controller: _password_controller,
                      suffixIcon: passwordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      iconAction: () {
                        setState(() {
                          passwordVisible = !passwordVisible;
                        });
                      },
                      textFieldLabel: "Password",
                      textFieldKeyboardType: TextInputType.visiblePassword,
                      textFieldObscureText: !passwordVisible,
                      textFieldOnChanged: (value) {},
                    ),
                    GB_buildTextField(
                      controller: _confirm_password_controller,
                      suffixIcon: confirmPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      iconAction: () {
                        setState(() {
                          confirmPasswordVisible = !confirmPasswordVisible;
                        });
                      },
                      textFieldLabel: "Re-enter Password",
                      textFieldKeyboardType: TextInputType.visiblePassword,
                      textFieldObscureText: !confirmPasswordVisible,
                      textFieldOnChanged: (value) {},
                    ),
                  ],
                ),
              ),
              Center(
                child: GB_ElevatedButtonString(
                  screenWidth: screenWidth,
                  horizontalPadding: 0.15,
                  verticalPadding: kElevatedButtonVerticalPadding,
                  elevatedButtonText:
                      isSubmitting ? "Changing..." : "Change Password",
                  buttonColor: kPrimaryColor1,
                  elevatedButtonTextColor: kPrimaryColor2,
                  elevatedButtonFontWeight: FontWeight.w500,
                  elevatedButtonTextSize: kElevatedButtonTextSize,
                  onPressed: isSubmitting ? null : _changePassword,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
