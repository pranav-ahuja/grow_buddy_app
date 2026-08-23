import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_VerifyEmail.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';

/// Step 1 of the password reset flow: collect the registered email ID.
///
/// Next steps: GB_VerifyEmail -> GB_CreateNewPassword.
class GB_ForgotPassword extends StatefulWidget {
  const GB_ForgotPassword({super.key});

  @override
  State<GB_ForgotPassword> createState() => _GB_ForgotPasswordState();
}

class _GB_ForgotPasswordState extends State<GB_ForgotPassword> {
  final TextEditingController _email_controller = TextEditingController();

  bool isSubmitting = false;

  @override
  void dispose() {
    _email_controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _sendResetCode() async {
    final email = _email_controller.text.trim();
    if (email.isEmpty) {
      _showSnack("Please enter your registered email ID");
      return;
    }

    setState(() => isSubmitting = true);
    // TODO(backend): POST the email to the password-reset request endpoint and
    // surface a GB_ApiException the way GB_Login does. Until that exists the
    // screen just moves on so the flow can be walked through end to end.
    try {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GB_VerifyEmail(emailID: email),
        ),
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
          appBarText: "Forgot Password",
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
                  "assets/images/forget_password_1.png",
                  height: 250.0,
                ),
              ),
              GB_H1HeadingText(
                inputText: "Please enter your registered email ID",
                inputTextAlign: TextAlign.left,
              ),
              GB_H2HeadingText(
                inputText:
                    "We will send a verification code to your registered email ID.",
                inputTextAlign: TextAlign.left,
              ),
              Container(
                margin: EdgeInsets.symmetric(vertical: 20.0),
                child: GB_buildTextField(
                  controller: _email_controller,
                  suffixIcon: Icons.cancel_outlined,
                  iconAction: () {
                    setState(() {
                      _email_controller.clear();
                    });
                  },
                  textFieldHintText: "abc@example.com",
                  textFieldLabel: "Email",
                  textFieldKeyboardType: TextInputType.emailAddress,
                  textFieldOnChanged: (value) {},
                ),
              ),
              Center(
                child: GB_ElevatedButtonString(
                  screenWidth: screenWidth,
                  horizontalPadding: 0.3,
                  verticalPadding: kElevatedButtonVerticalPadding,
                  elevatedButtonText: isSubmitting ? "Sending..." : "Next",
                  buttonColor: kPrimaryColor1,
                  elevatedButtonTextColor: kPrimaryColor2,
                  elevatedButtonFontWeight: FontWeight.w500,
                  elevatedButtonTextSize: kElevatedButtonTextSize,
                  onPressed: isSubmitting ? null : _sendResetCode,
                ),
              ),
              Center(
                child: GB_TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GB_MobileLogin(),
                      ),
                    );
                  },
                  textButtonColor: kPrimaryColor1,
                  textButtonText: "Try another way",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
