import 'package:flutter/material.dart';
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
              GB_H2HeadingText(
                inputText:
                    "\"Create your account or log in to continue.\nYour data is safe with us\"",
                inputTextAlign: TextAlign.center,
              ),
              GB_ElevatedButtonString(
                screenWidth: screenWidth,
                horizontalPadding: 0.27,
                buttonColor: kPrimaryColor1,
                elevatedButtonText: "Login",
                elevatedButtonTextColor: kPrimaryColor2,
                verticalPadding: 10.0,
                elevatedButtonFontWeight: FontWeight.w500,
                elevatedButtonTextSize: 18.0,
                onPressed: () {},
              ),
              GB_ElevatedButtonString(
                screenWidth: screenWidth,
                elevatedButtonText: "Sign up",
                buttonColor: kPrimaryColor2,
                elevatedButtonFontWeight: FontWeight.w500,
                elevatedButtonTextColor: kPrimaryColor1,
                elevatedButtonTextSize: 18.0,
                horizontalPadding: 0.25,
                verticalPadding: 10.0,
                onPressed: () {},
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GB_ElevatedButtonIcons(
                    elevatedButtonIcon: Logos.google_icon,
                    elevatedButtonIconSize: 30.0,
                    elevatedButtonPadding: 8.0,
                    onPressed: () {},
                  ),
                  GB_ElevatedButtonIcons(
                    elevatedButtonIcon: MaterialSymbols.call,
                    elevatedButtonIconSize: 30.0,
                    elevatedButtonPadding: 8.0,
                    onPressed: () {},
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