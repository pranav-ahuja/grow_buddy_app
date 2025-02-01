import 'package:flutter/material.dart';

//Constant Colors for the app
const Color kPrimaryColor1 = Color(0xff005B54);
const Color kPrimaryColor2 = Color(0xffffffff);
const Color kTextColor = Color(0xff000000);

//Floating Action Button Constants
const double kFloatingButtonCircularRadius = 15.0;
const double kFloatingButtonStrokeSize = 2.0;

//OnboardingPage Constants
const double kCarouselImageSliderHeight = 500.0;
const double kCarouselImageSliderViewPort = 1.0;

//Heading and Text Constants
const TextStyle kH1TextStyle = TextStyle(
  fontSize: 20,
  color: kTextColor,
  fontWeight: FontWeight.w500,
);
const TextStyle kH2TextStyle = TextStyle(
  fontSize: 15.0,
  color: kTextColor,
  fontWeight: FontWeight.w400,
);

//Elevated button Constants
const double kElevatedButtonVerticalPadding = 10.0;
const double kElevatedButtonTextSize = 18.0;
const double kElevatedButtonIconSize = 30.0;
const double kEvelatedButtonPadding = 8.0;

//Account Type
const int accountTypeTeacher = 0;
const int accountTypeStudent = 1;

//Http requests
const String kLoginUrl = 'http://192.168.0.157:8080/api/v1/authenticate';
