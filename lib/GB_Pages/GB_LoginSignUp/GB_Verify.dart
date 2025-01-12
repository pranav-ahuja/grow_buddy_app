import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:pinput/pinput.dart';

class GB_Verify extends StatefulWidget {
  const GB_Verify({super.key});

  @override
  State<GB_Verify> createState() => _GB_VerifyState();
}

class _GB_VerifyState extends State<GB_Verify> {
  Color nextButtonColor = Colors.white12;
  Color nextButtonTextColor = Colors.black54;

  String phoneNumber = "";
  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

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
                inputText: "Please enter the received OTP here",
                inputTextAlign: TextAlign.left,
              ),
              Container(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    Pinput(),
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
                    horizontalPadding: 0.30,
                    verticalPadding: 10.0,
                    elevatedButtonText: "Confirm",
                    buttonColor: kPrimaryColor1,
                    elevatedButtonTextColor: kPrimaryColor2,
                    elevatedButtonFontWeight: FontWeight.w500,
                    elevatedButtonTextSize: kElevatedButtonTextSize,
                    onPressed: () {},
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: GB_ElevatedButtonString(
                    screenWidth: screenWidth,
                    horizontalPadding: 0.25,
                    verticalPadding: 10.0,
                    elevatedButtonText: "Resend Code",
                    buttonColor: kPrimaryColor2,
                    elevatedButtonTextColor: kPrimaryColor1,
                    elevatedButtonFontWeight: FontWeight.w500,
                    elevatedButtonTextSize: kElevatedButtonTextSize,
                    onPressed: () {},
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
