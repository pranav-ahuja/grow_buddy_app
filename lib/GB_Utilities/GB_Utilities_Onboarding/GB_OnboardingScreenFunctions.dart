import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:colorful_iconify_flutter/icons/logos.dart';
import 'package:iconify_flutter/icons/material_symbols.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';

void loginSignUpPopUpCard(BuildContext context) {
  double screenWidth = MediaQuery.of(context).size.width;
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: EdgeInsets.symmetric(vertical: 10.0),
        alignment: Alignment.bottomCenter,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        elevation: 10.0,
        backgroundColor: kPrimaryColor2,
        child: Container(
          padding: EdgeInsets.only(top: 10.0),
          width: double.infinity,
          height: 350,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GB_H1HeadingText(
                inputText:
                    "\"Create your account or log in to continue.Your data is safe with us\"",
                inputTextAlign: TextAlign.center,
              ),
              GB_ElevatedButtonString(
                screenWidth: screenWidth,
                horizontalPadding: 0.2,
                buttonColor: kPrimaryColor1,
                elevatedButtonText: "Login",
                elevatedButtonTextColor: kPrimaryColor2,
                verticalPadding: kElevatedButtonVerticalPadding,
                elevatedButtonFontWeight: FontWeight.w500,
                elevatedButtonTextSize: kElevatedButtonTextSize,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GB_Login(),
                    ),
                  );
                },
              ),
              GB_ElevatedButtonString(
                screenWidth: screenWidth,
                elevatedButtonText: "Sign up",
                buttonColor: kPrimaryColor2,
                elevatedButtonFontWeight: FontWeight.w500,
                elevatedButtonTextColor: kPrimaryColor1,
                elevatedButtonTextSize: kElevatedButtonTextSize,
                horizontalPadding: 0.18,
                verticalPadding: kElevatedButtonVerticalPadding,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GB_SignUp(),
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GB_ElevatedButtonIcons(
                    elevatedButtonIcon: Logos.google_icon,
                    elevatedButtonIconSize: kElevatedButtonIconSize,
                    elevatedButtonPadding: kEvelatedButtonPadding,
                    onPressed: () {},
                  ),
                  GB_ElevatedButtonIcons(
                    elevatedButtonIcon: MaterialSymbols.call,
                    elevatedButtonIconSize: kElevatedButtonIconSize,
                    elevatedButtonPadding: kEvelatedButtonPadding,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GB_MobileLogin(),
                        ),
                      );
                    },
                  ),
                ],
              )
            ],
          ),
        ),
      );
    },
  );
}
