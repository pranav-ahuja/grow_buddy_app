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

// Four more pastels beyond the design's five, so a teacher choosing a colour has
// something to choose between. Mixed to the same recipe — a 50%-opacity wash
// over white under a 50%-opacity border of the same hue — so a class in one of
// these is indistinguishable in weight from a class in a design tint.
const Color kClassTilePeachFill = Color(0x80FFE7D6);
const Color kClassTilePeachBorder = Color(0x80D97D3A);
const Color kClassTileLavenderFill = Color(0x80E9E2FF);
const Color kClassTileLavenderBorder = Color(0x807B61C9);
const Color kClassTileAquaFill = Color(0x80D4F5F2);
const Color kClassTileAquaBorder = Color(0x80189B8E);
const Color kClassTileSageFill = Color(0x80E4EFD9);
const Color kClassTileSageBorder = Color(0x805F8A3A);

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
const double kClassDeleteIconSize = 22.0;
const double kHomeHorizontalPadding = 16.0;

//Class Colour Picker
// The swatch is a class tile in miniature: the same fill under the same border,
// so what is picked is literally what the dashboard will draw.
const double kClassSwatchSize = 36.0;
const double kClassSwatchGap = 10.0;
const double kClassSwatchBorderWidth = 1.0;
const double kClassSwatchSelectedBorderWidth = 2.0;
const double kClassSwatchCheckSize = 18.0;

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

//Class Screen
// From the Figma frame `360-45584`. The header panel carries the class's own
// tint and rounds off at the bottom; the feature and student rows are white
// cards on a faint vertical wash.
const double kClassPanelHeight = 352.0;
const double kClassPanelRadius = 24.0;
const double kClassAppBarTitleSize = 22.0;
const double kClassSectionHeaderSize = 18.0;
const double kClassWelcomeTextSize = 18.0;
const double kClassSeeAllTextSize = 12.0;

const double kFeatureCardWidth = 92.0;
const double kFeatureCardHeight = 120.0;
const double kFeatureCardRadius = 20.0;
const double kFeatureIconSize = 60.0;
const double kFeatureLabelTextSize = 14.0;
const double kFeatureRowGap = 24.0;

const double kStudentCardWidth = 92.0;
const double kStudentCardHeight = 120.0;
const double kStudentAvatarRadius = 28.0;
const double kStudentNameTextSize = 16.0;
/// The caption under a name on a student card. The design drew an age there;
/// the card shows the student id instead, at the same size.
const double kStudentIdTextSize = 12.0;
const double kStudentRowGap = 16.0;

/// Between the photo and the name on a student card.
const double kStudentCardGap = 4.0;
/// The card is a fixed height with three lines under the photo, so their
/// line height is pinned instead of left to the font, and the text stops
/// growing a little above the default size. Together these keep the card
/// from overflowing on a phone set to a larger font.
const double kStudentCardLineHeight = 1.2;
const double kStudentCardMaxTextScale = 1.1;

/// The faint top-to-bottom wash behind the horizontal card rows.
const Color kClassRowWashColor = Color(0xffF1F1F1);

/// Shared by the class cards, feature cards, and student cards.
const Color kClassCardShadowColor = Color(0x40E0DBDB);

//Register Student Sheet
// From the Figma frame `360-44515`. The sheet is a gold-edged card that fades
// from the app's cream to white, carrying a stack of outlined fields.
//
// The two alpha colours are Figma's own: rgba(201,149,1,0.5) for the sheet edge
// and rgba(90,73,3,0.5) for the field outlines. They are kept with their alpha
// rather than flattened because the sheet's own background is a gradient, so
// there is no single colour to flatten them onto.
const Color kSheetGradientTopColor = Color(0xffFFFCF3);
const Color kSheetBorderColor = Color(0x80C99501);
const Color kSheetHandleColor = Color(0x665A4903);
const Color kFieldBorderColor = Color(0x805A4903);

const double kSheetTopRadius = 28.0;
const double kSheetHorizontalPadding = 16.0;

/// The sheet's share of the screen. Below the full height so the dashboard
/// stays visible behind it and the sheet still reads as a sheet.
const double kSheetHeightFraction = 0.92;

const double kFieldRadius = 4.0;

/// Figma draws each field in a 76pt slot: a 56pt box with 20pt beneath it.
const double kFieldGap = 20.0;
const double kFieldRowGap = 16.0;
const double kFieldLabelTextSize = 12.0;
const double kFieldInputTextSize = 16.0;

const double kSheetIntroTextSize = 16.0;
const double kSheetSectionTextSize = 14.0;
const double kRegisterAvatarRadius = 40.0;

const double kPillButtonRadius = 100.0;
const double kPillButtonTextSize = 14.0;
const double kPillButtonHorizontalPadding = 20.0;
const double kPillButtonVerticalPadding = 10.0;

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

//OTP Constants
const double kOtpDigitTextSize = 26.0;

// How long GB_Verify keeps 'Resend Code' disabled. Mirrors the backend's
// OTP_RESEND_COOLDOWN_SECONDS in app/routers/auth.py -- if they disagree the
// button goes live before the server will accept a resend, and the user gets
// a rejection they did nothing to earn.
const int kOtpResendCooldownSeconds = 30;

//Elevated button Constants
const double kElevatedButtonVerticalPadding = 10.0;
const double kElevatedButtonTextSize = 18.0;
const double kElevatedButtonIconSize = 30.0;
const double kEvelatedButtonPadding = 8.0;

//Account Type
// These integers are the API's `account_type`, and they are mirrored in the
// backend's app/models.py. The backend maps them to the role text it stores
// ('teacher' / 'student' / 'principal'); the numbers themselves are written
// into every existing row, so they are append-only — never renumber them.
const int accountTypeTeacher = 0;
const int accountTypeStudent = 1;

/// The principal, who is the school's admin.
const int accountTypePrincipal = 2;

/// One choosable account type: the number the API wants, the word the user
/// reads, and the icon beside it.
class GB_AccountTypeOption {
  const GB_AccountTypeOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final int value;
  final String label;
  final IconData icon;
}

/// Every account type a person can pick, in the order they are offered.
///
/// One list rather than the same three choices restated in each picker. Before
/// this, the roles were written out separately in `GB_SignUp`, in
/// `DropDownTextFieldMenu`, and in `GB_CompleteProfile` — so adding the
/// principal meant three edits that could each be forgotten, and a role
/// missing from one screen is invisible until someone tries to sign up on it.
const List<GB_AccountTypeOption> kAccountTypeOptions = [
  GB_AccountTypeOption(
    value: accountTypeTeacher,
    label: "Teacher",
    icon: Icons.school_outlined,
  ),
  GB_AccountTypeOption(
    value: accountTypeStudent,
    label: "Student",
    icon: Icons.backpack_outlined,
  ),
  GB_AccountTypeOption(
    value: accountTypePrincipal,
    label: "Principal",
    icon: Icons.admin_panel_settings_outlined,
  ),
];

/// The label for an account type, for anywhere one has to be shown back to the
/// user. Null when the role was never chosen.
String? gAccountTypeLabel(int? value) {
  for (final GB_AccountTypeOption option in kAccountTypeOptions) {
    if (option.value == value) return option.label;
  }
  return null;
}

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
//   Anywhere, any network -> https://<machine>.<tailnet>.ts.net   (Tailscale)
//
// The default below is this machine's LAN address, which only reaches the
// backend while the phone is on the same Wi-Fi. Rather than editing this line
// for every network, override it at build time:
//
//   flutter run --dart-define=GB_API_BASE_URL=https://<machine>.<tailnet>.ts.net
//
// `tool/gb_tailscale_serve.ps1` starts the Tailscale proxy and prints that
// command with the real hostname filled in. The Tailscale form carries no port
// (serve listens on 443) and needs no network_security_config entry, because it
// is real HTTPS with a Let's Encrypt certificate rather than cleartext.
//
// `String.fromEnvironment` is a const constructor, so everything below stays a
// compile-time constant either way.
const String kApiBaseUrl = String.fromEnvironment(
  'GB_API_BASE_URL',
  defaultValue: 'http://192.168.0.157:8080',
);
const String kApiPrefix = '$kApiBaseUrl/api/v1';

const String kSignUpUrl = '$kApiPrefix/auth/signup';
const String kLoginUrl = '$kApiPrefix/auth/login';
const String kOtpRequestUrl = '$kApiPrefix/auth/otp/request';
const String kOtpVerifyUrl = '$kApiPrefix/auth/otp/verify';
const String kGoogleLoginUrl = '$kApiPrefix/auth/google';
// GET returns the current user; PATCH completes their profile.
const String kMeUrl = '$kApiPrefix/auth/me';

// Changing a contact you already have, which takes a code to the new address
// or number first. Separate from PATCH /auth/me on purpose: that route fills in
// a *missing* email or phone, while these two prove a replacement before it
// becomes the thing you log in with.
const String kContactChangeRequestUrl = '$kMeUrl/contact/request';
const String kContactChangeVerifyUrl = '$kMeUrl/contact/verify';

// What the two contact channels are called on the wire. Sent as a string the
// server CHECKs, so a typo here is a 422 and not a silently wrong column.
const String kContactChannelPhone = 'phone';
const String kContactChannelEmail = 'email';

// A teacher's classes and students. Everything under these is scoped to the
// signed-in user by the bearer token, which is what makes the same account show
// the same classes on every device.
const String kClassesUrl = '$kApiPrefix/classes';
const String kStudentsUrl = '$kApiPrefix/students';

// Both are role-scoped on the server: /students answers a teacher with their
// own pupils, the principal with the whole school, and a parent with their own
// children. The app sends no filter of its own, so it cannot get that filter
// wrong — which matters, because what is being filtered is other people's
// children.
const String kAttendanceUrl = '$kApiPrefix/attendance';
const String kSubjectsUrl = '$kApiPrefix/subjects';
const String kTeachersUrl = '$kApiPrefix/teachers';

/// The approval queue. A teacher's create/delete of a class, and their adding
/// or removing a pupil, land here as requests for the principal to answer;
/// see the backend's app/approvals.py.
const String kRequestsUrl = '$kApiPrefix/requests';

/// The notification tab — each account's own notices plus every broadcast.
const String kNotificationsUrl = '$kApiPrefix/notifications';
