import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_FloatingActionButton.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Utilities_Onboarding/GB_Image_Slider.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities//GB_Common_Classes.dart';

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
          onPressed: () => loginSignUpPopUpCard(),
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

  void loginSignUpPopUpCard() {
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
                      "\"Create your account or log in to continue.\nYour data is safe with us",
                  inputTextAlign: TextAlign.center,
                ),
                ElevatedButton(
                  onPressed: () {},
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Text(
                      "Login",
                      style: TextStyle(
                        color: kPrimaryColor2,
                        fontSize: 18.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all(kPrimaryColor1),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {},
                  child: Text("Sign Up"),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      child: Icon(Icons.mail),
                      style: ButtonStyle(
                        shape: MaterialStateProperty.all(
                          CircleBorder(),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {},
                      child: Icon(Icons.phone),
                      style: ButtonStyle(
                        shape: MaterialStateProperty.all(
                          CircleBorder(),
                        ),
                      ),
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
}
