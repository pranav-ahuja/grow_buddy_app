import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_FloatingActionButton.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Utilities_Onboarding/GB_Image_Slider.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Utilities_Onboarding/GB_OnboardingScreenFunctions.dart';

class OnBoardingPage extends StatefulWidget {
  const OnBoardingPage({super.key});

  @override
  State<OnBoardingPage> createState() => _OnBoardingPageState();
}

class _OnBoardingPageState extends State<OnBoardingPage> {
  List<String> sliderImageList = [
    "assets/images/home_page.png",
    "assets/images/home_page2.png",
    "assets/images/home_page3.png",
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        floatingActionButton: GB_FloatingActionButton(
          floatingActionButtonIcon: Icons.arrow_forward,
          floatingActionButtonBackgroundColor: kPrimaryColor2,
          floatingActionButtonForegroundColor: kPrimaryColor1,
          onPressed: () => loginSignUpPopUpCard(context),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GB_ImageSlider(sliderImageList: sliderImageList),
            GB_H1HeadingText(
              inputText: "Welcome to Grow Buddy!",
              inputTextAlign: TextAlign.center,
            ),
            GB_H2HeadingText(
              inputText:
                  "\“Your ultimate companion in managing \nyour classroom efficiently.\"",
              inputTextAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
