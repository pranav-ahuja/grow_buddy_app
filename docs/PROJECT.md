# GrowBuddy — Project Notes

School-management app (mobile + web planned) for GrowBuddy school. Flutter front
end, FastAPI back end.

## Stack
- Flutter 3.32.2 (Dart 3.8.1) — targets Android, iOS, Windows today
- Backend: Python 3.12 + FastAPI + SQLAlchemy, in `backend/` (see `backend/README.md`)
- HTTP client: `http` package, wrapped by `lib/GB_Services/` (base URL is `kApiBaseUrl` in `GB_Constants.dart`)
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
│       └── GB_Verify.dart                 OTP entry (Pinput), takes phoneNumber
├── GB_Services/
│   ├── GB_ApiClient.dart                  HTTP + error/timeout handling, GB_ApiException
│   └── GB_AuthApi.dart                    auth endpoints + GB_User / GB_AuthResult models
└── GB_Utilities/
    ├── GB_Common_Utilities/               shared widgets, constants, globals, functions
    ├── GB_Utilities_Onboarding/           carousel + login-signup popup helpers
    └── GB_FloatingActionButton.dart       shared FAB
assets/images/                              PNGs used across screens (incl. features_of_class/)
backend/                                    FastAPI service — see backend/README.md
```

## Current Flow (implemented)
`Splash → Onboarding (image carousel) → FAB opens dialog → Login | SignUp | Mobile Login → Verify (OTP)`

Login, SignUp, and OTP verify all hit the real backend and store a JWT in
`gLoginToken` via `gSetSession()`. Post-login navigation to Home/Dashboard is
**not yet built** — each screen ends at a `// TODO: Navigate to home/dashboard`.

## What's Left (from Figma)
- Forgot-password / password-reset screens (assets exist: `forget_password*.png`)
- "Who are you?" role-select screen (asset: `who_are_you.png`)
- Home dashboard (assets: `home_page*.png` — currently used only in onboarding carousel)
- Classes list + per-class detail (assets: `classes.jpeg`, `features_of_class/*`)
- Class features: Attendance, Assignments, Gradebook, Class schedule, Fee payment, Resources
- Events screen (asset: `event_images.png`)
- Post-login routing, and backend endpoints for everything above (only auth exists)
- Google sign-in: **backend is done**; the app still needs the `google_sign_in`
  package, OAuth client IDs from Google Cloud, and the buttons wired up (they
  are no-ops in `GB_SignUp.dart` and `GB_OnboardingScreenFunctions.dart`)
- Login page has no Google or phone buttons yet, unlike SignUp and the onboarding popup

## Design Conventions in the Code
- File and class names use `GB_` prefix and `Snake_Case`/PascalCase (linter flags this as non-idiomatic, but it's the project's chosen convention — do not mass-rename without discussion).
- Colors and reusable sizes live in `GB_Constants.dart` (`kPrimaryColor1` = teal `#005B54`, `kPrimaryColor2` = white).
- Global auth token stored in `GB_Globals.dart` → `gLoginToken` (temporary — should move to secure storage before shipping).

## Backend
Python 3.12 + FastAPI + SQLAlchemy in `backend/`, auth only so far. Full details,
run instructions, and the production checklist live in `backend/README.md`.

Endpoints under `/api/v1/auth`: `signup`, `login`, `otp/request`, `otp/verify`,
`google`, `me` (GET + PATCH). Success returns
`{access_token, token_type, is_new_user, user}`; every error returns
`{"detail": "<message>"}`, which the app shows verbatim in a SnackBar.

`account_type` is **null** for Google and phone sign-ups — neither identifies a
teacher vs a student, and phone sign-ups have no name either (placeholder
`"GrowBuddy User"`). Those responses carry `needs_account_type: true`: send the
user to a sign-up screen for name + role, then `PATCH /auth/me`.
**Route on `needs_account_type`, not `is_new_user`** — someone who abandoned the
screen is no longer new but still has no role.

Google accounts are identified by Google's permanent `sub` claim, never by
email; a changed email updates the existing row rather than creating a second
account. See `backend/README.md` for the reasoning and the collision rules.

Interactive docs at `http://<host>:8080/docs` — that page is the source of truth
for request/response shapes.

Notes that bite:
- `kApiBaseUrl` differs per target: `10.0.2.2` (Android emulator), `127.0.0.1`
  (desktop/iOS sim), LAN IP (physical phone).
- Android 9+ blocks plain HTTP. `android/app/src/debug/res/xml/network_security_config.xml`
  allow-lists dev hosts for debug builds only; a changed LAN IP must be updated
  there **and** in `GB_Constants.dart`.
- OTP has no SMS provider yet. With `OTP_DEBUG_RETURN=true` the code comes back
  in the response and the app shows it as `(dev code: 123456)`.
- Storage defaults to SQLite (`backend/growbuddy.db`, git-ignored); switch
  `DATABASE_URL` for PostgreSQL.

## Recent Fixes (see git diff)
1. Added missing `colorful_iconify_flutter` dependency (was imported, undeclared).
2. Declared `assets/images/features_of_class/` in `pubspec.yaml`.
3. `GB_Common_Functions.dart` — dead-code `obscureText` condition that could never be true; simplified to use the passed param.
4. `GB_SignUp.dart` — password visibility icon and hidden-state were inverted vs. Login; aligned.
5. `GB_CommonDropDownMenuField.dart` — rewrote (was uninitialised `late int` + 1000px border).
6. `GB_MobileLogin.dart` — typos ("ypur", "Phone Up").
7. Built the FastAPI backend and wired the auth screens to it through `GB_Services/`.
   Removed the guess-the-token-shape fallback in `GB_Login.dart`; the contract is fixed now.
8. `GB_MobileLogin.dart` — phone was captured as `value.toString()` (the `PhoneNumber`
   object's description) instead of `value.completeNumber`, so it could never have
   been sent to a server correctly.
9. `GB_SignUp.dart` — `accountType` defaulted to `0`, silently registering anyone who
   skipped the dropdown as a teacher; it is now nullable and required.
10. `AndroidManifest.xml` — added the `INTERNET` permission to the **main** manifest
    (it was debug-only, so release builds would have had no network at all) plus a
    debug-only cleartext allow-list.

## Verification
- `flutter analyze` → 0 errors, 0 warnings (98 pre-existing style hints: const/camelCase/file_names, from the project's `GB_` convention).
- `flutter build apk --debug` → succeeds; merged manifest carries `networkSecurityConfig`.
- `cd backend && .venv\Scripts\python.exe -m pytest -q` → 14 passed.