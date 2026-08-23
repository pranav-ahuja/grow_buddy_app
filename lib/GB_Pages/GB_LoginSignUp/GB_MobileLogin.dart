import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Verify.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';

class GB_MobileLogin extends StatefulWidget {
  const GB_MobileLogin({super.key});

  @override
  State<GB_MobileLogin> createState() => _GB_MobileLoginState();
}

class _GB_MobileLoginState extends State<GB_MobileLogin> {
  Color nextButtonColor = Colors.white12;
  Color nextButtonTextColor = Colors.black54;

  String phoneNumber = "";
  bool isSubmitting = false;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _requestOtp() async {
    if (phoneNumber.isEmpty) {
      _showSnack("Please enter your mobile number");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final result = await GB_AuthApi.requestOtp(phoneNumber);

      // Carries the dev code in a debug build; plain wording otherwise.
      _showSnack(result.displayMessage);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GB_Verify(phoneNumber: phoneNumber),
        ),
      );
    } on GB_ApiException catch (error) {
      _showSnack(error.message);
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
                inputText: "Enter your Mobile Number",
                inputTextAlign: TextAlign.left,
              ),
              GB_H2HeadingText(
                inputText:
                    "Please confirm your country code and enter your mobile number",
                inputTextAlign: TextAlign.left,
              ),
              Container(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    IntlPhoneField(
                      decoration: InputDecoration(
                        label: Text("Phone Number"),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50.0),
                          borderSide: BorderSide(
                            color: kPrimaryColor1,
                          ),
                        ),
                      ),
                      initialCountryCode: 'IN',
                      onChanged: (value) {
                        setState(() {
                          // completeNumber is "+919876543210"; toString() would
                          // hand back the PhoneNumber object's description.
                          phoneNumber = value.completeNumber;
                          if (phoneNumber.isNotEmpty) {
                            nextButtonColor = kPrimaryColor1;
                            nextButtonTextColor = kPrimaryColor2;
                          } else if (phoneNumber.isEmpty) {
                            nextButtonColor = Colors.white12;
                            nextButtonTextColor = Colors.black54;
                          }
                        });
                      },
                    ),
                    Text(
                        "We'll text you a code to verify. Message and data rate may apply."),
                  ],
                ),
              ),
              Center(
                child: GB_ElevatedButtonString(
                  screenWidth: screenWidth,
                  horizontalPadding: 0.2,
                  verticalPadding: 10.0,
                  elevatedButtonText: isSubmitting ? "Sending..." : "Next",
                  buttonColor: nextButtonColor,
                  elevatedButtonTextColor: nextButtonTextColor,
                  elevatedButtonFontWeight: FontWeight.w500,
                  elevatedButtonTextSize: kElevatedButtonTextSize,
                  onPressed: isSubmitting ? null : _requestOtp,
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
