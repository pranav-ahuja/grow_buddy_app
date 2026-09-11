import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:pinput/pinput.dart';

class GB_Verify extends StatefulWidget {
  const GB_Verify({super.key, required this.phoneNumber});

  /// Full number in E.164 form, e.g. "+919876543210".
  final String phoneNumber;

  @override
  State<GB_Verify> createState() => _GB_VerifyState();
}

class _GB_VerifyState extends State<GB_Verify> {
  final TextEditingController _otpController = TextEditingController();

  bool isSubmitting = false;
  bool isResending = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      _showSnack("Please enter the code we sent you");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final result = await GB_AuthApi.verifyOtp(
        phone: widget.phoneNumber,
        otp: otp,
      );

      if (!mounted) return;
      // Sets the session and picks the destination from needsAccountType. A
      // phone sign-up has no role yet, so a new user lands on the profile
      // screen; a returning one who already picked a role goes to the dashboard.
      gRouteAfterAuth(context, result);
    } on GB_ApiException catch (error) {
      _showSnack(error.message);
      _otpController.clear();
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => isResending = true);
    try {
      final result = await GB_AuthApi.requestOtp(widget.phoneNumber);
      _showSnack(result.displayMessage);
    } on GB_ApiException catch (error) {
      _showSnack(error.message);
    } finally {
      if (mounted) setState(() => isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    // Pinput's own default cell, restated so the digits can be made larger.
    final PinTheme defaultPinTheme = PinTheme(
      width: 56.0,
      height: 60.0,
      textStyle: TextStyle(
        fontSize: kOtpDigitTextSize,
        color: kTextColor,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(222, 231, 240, .57),
        borderRadius: BorderRadius.circular(8.0),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: GB_AppBarText(
          appBarText: "Phone Login",
          appBarFontWeight: FontWeight.w500,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset("assets/images/login_page.png"),
              GB_H1HeadingText(
                inputText: "Enter OTP",
                inputTextAlign: TextAlign.left,
              ),
              GB_H2HeadingText(
                inputText: "Please enter the OTP sent to ${widget.phoneNumber}",
                inputTextAlign: TextAlign.left,
              ),
              Container(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    Pinput(
                      controller: _otpController,
                      length: 6,
                      defaultPinTheme: defaultPinTheme,
                      onCompleted: (_) => _confirmOtp(),
                    ),
                    Text(
                        "We'll text you a code to verify. Message and data rate may apply."),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: GB_ElevatedButtonString(
                    screenWidth: screenWidth,
                    horizontalPadding: 0.25,
                    verticalPadding: 10.0,
                    elevatedButtonText:
                        isSubmitting ? "Verifying..." : "Confirm",
                    buttonColor: kPrimaryColor1,
                    elevatedButtonTextColor: kPrimaryColor2,
                    elevatedButtonFontWeight: FontWeight.w500,
                    elevatedButtonTextSize: kElevatedButtonTextSize,
                    onPressed: isSubmitting ? null : _confirmOtp,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: GB_ElevatedButtonString(
                    screenWidth: screenWidth,
                    horizontalPadding: 0.2,
                    verticalPadding: 10.0,
                    elevatedButtonText:
                        isResending ? "Sending..." : "Resend Code",
                    buttonColor: kPrimaryColor2,
                    elevatedButtonTextColor: kPrimaryColor1,
                    elevatedButtonFontWeight: FontWeight.w500,
                    elevatedButtonTextSize: kElevatedButtonTextSize,
                    onPressed: isResending ? null : _resendOtp,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Center(
                  child: GB_TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GB_SignUp(),
                        ),
                      );
                    },
                    textButtonColor: Colors.black54,
                    textButtonText: "New to Grow Buddy? Sign up now",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
