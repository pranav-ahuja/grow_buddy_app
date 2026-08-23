import 'package:flutter/material.dart';

//Constant Colors for the app
const Color kPrimaryColor1 = Color(0xff005B54);
const Color kPrimaryColor2 = Color(0xffffffff);
const Color kTextColor = Color(0xff000000);

//Home Screen (Dashboard) Colors
// Taken from the Figma frame `360-39838` of the GROW BUDDY file, which is the
// source of truth for this screen. Values that Figma declares with alpha are
// kept as alpha here rather than pre-flattened onto white, so they stay correct
// if the page background ever changes.
//
// kHomeAccentColor is Figma's published style "3A" and is a shade off the app's
// kPrimaryColor1 (#005B54). Both are kept because the design says #02685F for
// this screen while the rest of the app already ships #005B54.
const Color kHomeAccentColor = Color(0xff02685F);
const Color kHomeTitleTextColor = Color(0xff383838);
const Color kHomeSubtitleTextColor = Color(0xff666666);
const Color kHomeIconColor = Color(0xff383838);
const Color kHomeAppBarBorderColor = Color(0x66C99501);
const Color kHomeCardBorderColor = Color(0x1A000000);
const Color kHomeNavBorderColor = Color(0xffBBBBBB);
const Color kHomeDotColor = Color(0xff666666);

// Class card tints, in the order they appear on the design's list. Every pair
// is a 50%-opacity fill over white with a 50%-opacity border of the same hue —
// the borders are far more saturated than they look once composited.
const Color kClassTileYellowFill = Color(0xffFFFCF3);
const Color kClassTileYellowBorder = Color(0x80C99501);
const Color kClassTilePinkFill = Color(0x80FFEEEC);
const Color kClassTilePinkBorder = Color(0x80F2B1A9);
const Color kClassTileBlueFill = Color(0x80E1F6FF);
const Color kClassTileBlueBorder = Color(0x8051B3E0);
const Color kClassTileGreenFill = Color(0x80D7FFEE);
const Color kClassTileGreenBorder = Color(0x8002685F);
const Color kClassTilePurpleFill = Color(0x80FFD7F9);
const Color kClassTilePurpleBorder = Color(0x80A2008A);

//Home Screen Sizing
// The design is drawn on a 360x800 screen; the fractions below reproduce its
// 328pt card on a 344pt pitch so the neighbouring cards peek by the same amount
// on any width.
const double kEventCardWidthFraction = 344.0 / 360.0;
const double kEventCardGutter = 8.0;
const double kEventCardHeight = 240.0;
const double kEventImageHeight = 140.0;
const double kEventCardPadding = 14.0;
const double kEventCardRadius = 24.0;
const double kClassTileRadius = 12.0;
const double kClassTilePadding = 16.0;
const double kClassTileGap = 12.0;
const double kClassTileAvatarRadius = 24.0;
const double kHomeHorizontalPadding = 16.0;

//Home Screen Text Sizes
const double kHomeAppBarTextSize = 24.0;
const double kHomeSectionHeaderTextSize = 20.0;
const double kHomeCardTitleTextSize = 20.0;
const double kEventSubtitleTextSize = 14.0;
const double kClassSubtitleTextSize = 12.0;
const double kHomeNavSelectedTextSize = 14.0;
const double kHomeNavUnselectedTextSize = 12.0;

//Home Screen Assets
const String kClassAvatarImage = "assets/images/hs_classes.jpeg";
const String kEventImage = "assets/images/hs_events.png";

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

//Google Sign-In
// Both come from Google Cloud Console -> APIs & Services -> Credentials, and
// must also be listed in the backend's GOOGLE_CLIENT_IDS (see backend/README.md)
// or POST /auth/google rejects the token.
//
// This is the *Web* OAuth client ID, not the Android one. Android passes it as
// `serverClientId`, and its value is what lands in the ID token's `aud` claim.
const String kGoogleServerClientId =
    "444933759758-2maju3kl1la9t0qes0vnavppg8mg0910.apps.googleusercontent.com";

// The iOS OAuth client ID. Android ignores this; leave it empty until iOS ships.
// TODO: fill in from Google Cloud Console
const String kGoogleIosClientId = "";

//Http requests
// Point this at the machine running backend/ (see backend/README.md).
//   Android emulator      -> http://10.0.2.2:8080
//   iOS simulator/desktop -> http://127.0.0.1:8080
//   Physical device       -> http://<your-computer-LAN-IP>:8080
const String kApiBaseUrl = 'http://192.168.0.157:8080';
const String kApiPrefix = '$kApiBaseUrl/api/v1';

const String kSignUpUrl = '$kApiPrefix/auth/signup';
const String kLoginUrl = '$kApiPrefix/auth/login';
const String kOtpRequestUrl = '$kApiPrefix/auth/otp/request';
const String kOtpVerifyUrl = '$kApiPrefix/auth/otp/verify';
const String kGoogleLoginUrl = '$kApiPrefix/auth/google';
// GET returns the current user; PATCH completes their profile.
const String kMeUrl = '$kApiPrefix/auth/me';
