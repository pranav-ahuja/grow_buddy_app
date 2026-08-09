# GrowBuddy — Project Notes

School-management app (mobile + web planned) for GrowBuddy school. Built with Flutter.

## Stack
- Flutter 3.32.2 (Dart 3.8.1) — targets Android, iOS, Windows today
- HTTP client: `http` package (backend auth at `kLoginUrl` in `GB_Constants.dart`)
- UI helpers: `carousel_slider`, `dropdown_button2`, `intl_phone_field`, `pinput`, `iconify_flutter`, `colorful_iconify_flutter`, `another_flutter_splash_screen`

## Folder Layout
```
lib/
├── main.dart                              app entry + splash screen
├── GB_Pages/
│   ├── GB_Startup/GB_OnboardingPage.dart  carousel + welcome + FAB → login/signup dialog
│   └── GB_LoginSignUp/
│       ├── GB_Login.dart                  email + password login (hits backend)
│       ├── GB_SignUp.dart                 full form (name/email/pw/type)
│       ├── GB_MobileLogin.dart            phone-number entry
│       └── GB_Verify.dart                 OTP entry (Pinput)
└── GB_Utilities/
    ├── GB_Common_Utilities/               shared widgets, constants, globals, functions
    ├── GB_Utilities_Onboarding/           carousel + login-signup popup helpers
    └── GB_FloatingActionButton.dart       shared FAB
assets/images/                              PNGs used across screens (incl. features_of_class/)
```

## Current Flow (implemented)
`Splash → Onboarding (image carousel) → FAB opens dialog → Login | SignUp | Mobile Login → Verify (OTP)`

Post-login navigation to Home/Dashboard is **not yet built**.

## What's Left (from Figma)
- Forgot-password / password-reset screens (assets exist: `forget_password*.png`)
- "Who are you?" role-select screen (asset: `who_are_you.png`)
- Home dashboard (assets: `home_page*.png` — currently used only in onboarding carousel)
- Classes list + per-class detail (assets: `classes.jpeg`, `features_of_class/*`)
- Class features: Attendance, Assignments, Gradebook, Class schedule, Fee payment, Resources
- Events screen (asset: `event_images.png`)
- Actual backend wiring for SignUp, OTP verify, and post-login routing

## Design Conventions in the Code
- File and class names use `GB_` prefix and `Snake_Case`/PascalCase (linter flags this as non-idiomatic, but it's the project's chosen convention — do not mass-rename without discussion).
- Colors and reusable sizes live in `GB_Constants.dart` (`kPrimaryColor1` = teal `#005B54`, `kPrimaryColor2` = white).
- Global auth token stored in `GB_Globals.dart` → `gLoginToken` (temporary — should move to secure storage before shipping).

## Backend
- Single endpoint so far: `POST kLoginUrl` (`http://192.168.0.157:8080/api/v1/authenticate`), body `{email, password}`, returns 200 with token.
- **TODOs marked in code:** exact response shape for login, error payload contract, post-login navigation target.

## Recent Fixes (see git diff)
1. Added missing `colorful_iconify_flutter` dependency (was imported, undeclared).
2. Declared `assets/images/features_of_class/` in `pubspec.yaml`.
3. `GB_Common_Functions.dart` — dead-code `obscureText` condition that could never be true; simplified to use the passed param.
4. `GB_SignUp.dart` — password visibility icon and hidden-state were inverted vs. Login; aligned.
5. `GB_CommonDropDownMenuField.dart` — rewrote (was uninitialised `late int` + 1000px border).
6. `GB_Login.dart` — `authenticate_login` now validates input, tolerates JSON or plain-string token responses, handles non-200 and network errors via SnackBar, updates `gLoginToken` only on success.
7. `GB_MobileLogin.dart` — typos ("ypur", "Phone Up").

## Verification
`flutter analyze` → 0 errors, 0 warnings (only ~90 style hints remain: const/camelCase/prefer_typed_variables).