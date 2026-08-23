import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_CreateNewPassword.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:pinput/pinput.dart';

/// Step 2 of the password reset flow: confirm the code mailed to [emailID].
///
/// Separate from GB_Verify, which verifies a *phone* number and signs the user
/// in on success. This one only proves the mailbox belongs to them, then hands
/// off to GB_CreateNewPassword.
class GB_VerifyEmail extends StatefulWidget {
  const GB_VerifyEmail({super.key, required this.emailID});

  final String emailID;

  @override
  State<GB_VerifyEmail> createState() => _GB_VerifyEmailState();
}

class _GB_VerifyEmailState extends State<GB_VerifyEmail> {
  final TextEditingController _otp_controller = TextEditingController();

  bool isSubmitting = false;
  bool isResending = false;

  @override
  void dispose() {
    _otp_controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmCode() async {
    final otp = _otp_controller.text.trim();
    if (otp.length < 6) {
      _showSnack("Please enter the 6 digit code we emailed you");
      return;
    }

    setState(() => isSubmitting = true);
    // TODO(backend): verify the code against the reset endpoint and carry the
    // reset token it returns into GB_CreateNewPassword.
    try {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GB_CreateNewPassword(emailID: widget.emailID),
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => isResending = true);
    // TODO(backend): re-request the reset code for widget.emailID.
    try {
      _showSnack("Verification code sent to ${widget.emailID}");
    } finally {
      if (mounted) setState(() => isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    // The design shows the code as six underlines rather than boxed cells.
    final PinTheme defaultPinTheme = PinTheme(
      width: 40.0,
      height: 50.0,
      textStyle: TextStyle(
        fontSize: 20.0,
        color: kTextColor,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.black54, width: 2.0),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: GB_AppBarText(
          appBarText: "Verify Your Email",
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
                  "assets/images/forget_password_2.png",
                  height: 250.0,
                ),
              ),
              GB_H1HeadingText(
                inputText: "Please enter your verification code",
                inputTextAlign: TextAlign.left,
              ),
              GB_H2HeadingText(
                inputText:
                    "We have sent a verification code to ${widget.emailID}",
                inputTextAlign: TextAlign.left,
              ),
              Container(
                margin: EdgeInsets.symmetric(vertical: 30.0),
                child: Center(
                  child: Pinput(
                    controller: _otp_controller,
                    length: 6,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: defaultPinTheme.copyWith(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: kPrimaryColor1, width: 2.0),
                        ),
                      ),
                    ),
                    onCompleted: (_) => _confirmCode(),
                  ),
                ),
              ),
              Center(
                child: GB_ElevatedButtonString(
                  screenWidth: screenWidth,
                  horizontalPadding: 0.3,
                  verticalPadding: kElevatedButtonVerticalPadding,
                  elevatedButtonText: isSubmitting ? "Verifying..." : "Done",
                  buttonColor: kPrimaryColor1,
                  elevatedButtonTextColor: kPrimaryColor2,
                  elevatedButtonFontWeight: FontWeight.w500,
                  elevatedButtonTextSize: kElevatedButtonTextSize,
                  onPressed: isSubmitting ? null : _confirmCode,
                ),
              ),
              Center(
                child: GB_TextButton(
                  onPressed: isResending ? null : _resendCode,
                  textButtonColor: kPrimaryColor1,
                  textButtonText: isResending ? "Sending..." : "Resend Code",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
