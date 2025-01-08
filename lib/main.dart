import 'package:flutter/material.dart';
import 'package:another_flutter_splash_screen/another_flutter_splash_screen.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Startup/GB_OnboardingPage.dart';

void main() {
  runApp(const GroweBuddyMain());
}

class GroweBuddyMain extends StatelessWidget {
  const GroweBuddyMain({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FlutterSplashScreen.fadeIn(
        backgroundColor: kPrimaryColor2,
        onInit: () {
          print("On Init");
        },
        onEnd: () {
          print("On End");
        },
        childWidget: SizedBox(
          height: 500.0,
          width: 500.0,
          child: Image.asset(
            "assets/images/splash_image.png",
          ),
        ),
        onAnimationEnd: () => print("On Fade In End"),
        nextScreen: OnBoardingPage(),
      ),
    );
  }
}
