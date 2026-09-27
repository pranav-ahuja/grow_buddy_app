import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pinput/pinput.dart';

/// Placeholder the backend gives phone sign-ups, which arrive with no real
/// name. Treated as "no name yet" so the field starts empty rather than asking
/// the user to delete it — the same reading `GB_CompleteProfile` gives it.
const String _kPlaceholderName = "GrowBuddy User";

/// Which half of the sheet is on screen.
enum _Step { details, code }

/// Edits the signed-in user's own basic details — name, email, mobile number.
///
/// **The name and the contacts are saved by different routes, on purpose.** A
/// name is only ever a label, so "Save name" sends it to `PATCH /auth/me` and
/// it is done. An email or a number is what the account signs in with, so it
/// goes through `POST /auth/me/contact/request` and then
/// `/contact/verify`: the value is held server-side until a code sent to it
/// comes back, and only then written to the user row. Until that moment the
/// old contact is still the one that logs in — which is what stops a mistyped
/// number from locking somebody out of the OTP screen the app opens on.
///
/// So each contact grows its own **Verify** button the moment it stops matching
/// the account, and the sheet switches to a code step for that one channel.
/// One channel at a time because a code belongs to one value: two at once would
/// mean two pending codes and a screen that has to explain which is which.
///
/// **Why this is not `GB_CompleteProfile`.** That screen owns `PATCH /auth/me`
/// too, and reusing it was the plan recorded in docs/PROJECT.md, but it is
/// built as a one-way gate and every part of that fights an edit: it *hides* a
/// field that is already filled (exactly the field being edited here), its back
/// arrow signs out because nothing is on the stack behind it, it finishes with
/// `pushAndRemoveUntil` onto the dashboard, and it sends a contact only when
/// that contact was missing. Making it do both means a mode flag threaded
/// through the fields, the copy, the app bar, the pop behaviour and the
/// payload — five branches, on a screen every new user has to pass through.
///
/// **The role is not here, deliberately.** It decides what the whole app will
/// let this account do, and since phase 5 a principal is the school's
/// administrator — so it is not a detail its owner corrects on their own
/// profile. `PATCH /auth/me` does currently accept `account_type` from anyone;
/// this sheet never sends it.
///
/// Call [show]; it returns the user as they now are if anything was saved, or
/// null if nothing was.
class GB_EditProfileSheet extends StatefulWidget {
  const GB_EditProfileSheet({super.key, required this.user});

  final GB_User user;

  static Future<GB_User?> show(BuildContext context, GB_User user) {
    return showModalBottomSheet<GB_User>(
      context: context,
      backgroundColor: kPrimaryColor2,
      // The keyboard would otherwise cover the fields and the button.
      isScrollControlled: true,
      // A code is on its way to a number by the time the second step is up, so
      // a stray tap outside should not throw it away silently.
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kClassPanelRadius),
        ),
      ),
      builder: (BuildContext context) => GB_EditProfileSheet(user: user),
    );
  }

  @override
  State<GB_EditProfileSheet> createState() => _GB_EditProfileSheetState();
}

class _GB_EditProfileSheetState extends State<GB_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();

  /// The account as the server last told us it is — re-based every time
  /// something commits, so "has this field changed?" is asked against what is
  /// really stored and a Verify button disappears once its value has landed.
  late GB_User _user;

  /// The full number in the form the backend stores and OTP login looks up —
  /// "+919876543210". Seeded from the account, because `IntlPhoneField` only
  /// reports a number once the user types in it: left empty, an untouched field
  /// would read as a cleared one.
  late String _phone;

  _Step _step = _Step.details;

  /// Which contact the code on screen belongs to, and the value the server said
  /// it sent that code to. Null while no code is outstanding.
  String? _pendingChannel;
  String? _pendingValue;

  String? _nameError;
  String? _emailError;
  String? _phoneError;

  /// Shown under the Pinput on the code step.
  String? _codeError;

  /// The code the server handed back while `OTP_DEBUG_RETURN` is on.
  ///
  /// Login shows this in a SnackBar through
  /// [GB_ContactChangeResult.displayMessage], and so does this sheet — but a
  /// modal bottom sheet is drawn *over* the SnackBar, so here the snack is the
  /// half that gets covered. Held so the code step can print it somewhere it
  /// cannot be hidden, under the same [kDebugMode] guard that keeps it off a
  /// release build however the server is configured.
  String? _debugOtp;

  bool _isSavingName = false;
  bool _isSendingCode = false;
  bool _isVerifying = false;

  /// True once anything at all has been committed, so dismissing the sheet
  /// after a successful verify still hands the fresh user back to the profile
  /// screen rather than looking like a cancel.
  bool _didCommit = false;

  Timer? _resendTimer;
  int _secondsUntilResend = 0;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    final String name = _user.fullName;
    _nameController = TextEditingController(
      text: name == _kPlaceholderName ? "" : name,
    );
    _emailController = TextEditingController(text: _user.email ?? "");
    _phone = _user.phone ?? "";
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Digits only, so "+91 98765 43210" and "+919876543210" compare equal. The
  /// backend strips spaces and dashes on the way in, so a stored number is
  /// already clean — but what the country picker hands back need not be.
  static String _digits(String value) => value.replaceAll(RegExp(r"\D"), "");

  String get _typedEmail => _emailController.text.trim().toLowerCase();

  bool get _emailChanged => _typedEmail != (_user.email ?? "").toLowerCase();

  bool get _phoneChanged => _digits(_phone) != _digits(_user.phone ?? "");

  bool get _nameChanged => _nameController.text.trim() != _user.fullName;

  bool get _isBusy => _isSavingName || _isSendingCode || _isVerifying;

  /// Counts the resend button down from [kOtpResendCooldownSeconds], which
  /// mirrors the server's own cooldown. If the button went live first the user
  /// would earn a 429 they did nothing to cause.
  void _startResendCooldown() {
    _resendTimer?.cancel();
    _secondsUntilResend = kOtpResendCooldownSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsUntilResend--);
      if (_secondsUntilResend <= 0) timer.cancel();
    });
  }

  /// What the one button at the bottom is for, in priority order.
  ///
  /// A contact that has been typed but not proved is the outstanding job on
  /// this sheet, so it wins: the button reads **Verify** rather than Done,
  /// because Done over an unverified number would say the edit had finished
  /// when the account had not moved at all. The number goes first when both
  /// have changed — a code belongs to one value, so they are proved one at a
  /// time, and the email's turn comes when the sheet returns here.
  String get _primaryLabel {
    if (_isSavingName) return "Saving…";
    if (_isSendingCode) return "Sending…";
    if (_phoneChanged) return "Verify mobile number";
    if (_emailChanged) return "Verify email address";
    if (_nameChanged) return "Save name";
    return "Done";
  }

  void _onPrimaryPressed() {
    if (_phoneChanged) {
      _sendCode(kContactChannelPhone);
    } else if (_emailChanged) {
      _sendCode(kContactChannelEmail);
    } else {
      // Saves the name, or simply closes when nothing was touched.
      _saveName();
    }
  }

  /// Closes the sheet, handing back the user if anything was saved.
  void _close() => Navigator.of(context).pop(_didCommit ? _user : null);

  // --- Saving the name -----------------------------------------------------

  Future<void> _saveName() async {
    if (_isBusy) return;

    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = "Please enter your full name");
      return;
    }
    if (!_nameChanged) {
      _close();
      return;
    }

    final String? token = gLoginToken;
    if (token == null) {
      _close();
      return;
    }

    setState(() {
      _isSavingName = true;
      _nameError = null;
    });

    try {
      // Only the name. A contact is never sent from here, so this call cannot
      // move an email or a number without the code that proves it.
      final GB_User updated = await GB_AuthApi.updateProfile(
        token: token,
        fullName: name,
      );
      await gUpdateCurrentUser(updated);
      if (!mounted) return;
      _didCommit = true;
      _user = updated;
      _close();
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingName = false;
        _nameError = error.message;
      });
    }
  }

  // --- Changing a contact --------------------------------------------------

  /// Validates the typed value, asks the server to send a code to it, and moves
  /// to the code step.
  Future<void> _sendCode(String channel) async {
    if (_isBusy) return;

    final bool isPhone = channel == kContactChannelPhone;
    final String value = isPhone ? _phone : _typedEmail;

    if (isPhone) {
      if (_digits(value).length < 7) {
        setState(() => _phoneError = "Enter your mobile number");
        return;
      }
    } else if (!RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(value)) {
      setState(() => _emailError = "Enter a valid email address");
      return;
    }

    final String? token = gLoginToken;
    if (token == null) {
      _close();
      return;
    }

    setState(() {
      _isSendingCode = true;
      _emailError = null;
      _phoneError = null;
    });

    try {
      final GB_ContactChangeResult sent = await GB_AuthApi.requestContactChange(
        token: token,
        channel: channel,
        value: value,
      );
      if (!mounted) return;
      setState(() {
        _isSendingCode = false;
        _step = _Step.code;
        // The server's normalised value, not the field's: what a code was sent
        // to is what the server stored.
        _pendingChannel = sent.channel;
        _pendingValue = sent.value;
        _debugOtp = sent.debugOtp;
        _codeController.clear();
        _codeError = null;
      });
      _startResendCooldown();
      // displayMessage carries the dev code in debug builds only, which is the
      // only way to read it while there is no SMS or email provider.
      gShowSnack(context, sent.displayMessage);
    } on GB_ApiException catch (error) {
      // 400 "already your number", 409 "used by another account", 429 cooldown
      // — all written for the user, and all about the field they just typed.
      if (!mounted) return;
      setState(() {
        _isSendingCode = false;
        if (isPhone) {
          _phoneError = error.message;
        } else {
          _emailError = error.message;
        }
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_isBusy) return;

    final String channel = _pendingChannel ?? kContactChannelPhone;
    final String code = _codeController.text.trim();
    if (code.length < 4) {
      setState(() => _codeError = "Enter the code we sent you");
      return;
    }

    final String? token = gLoginToken;
    if (token == null) {
      _close();
      return;
    }

    setState(() {
      _isVerifying = true;
      _codeError = null;
    });

    try {
      final GB_User updated = await GB_AuthApi.verifyContactChange(
        token: token,
        channel: channel,
        otp: code,
      );
      await gUpdateCurrentUser(updated);
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _isVerifying = false;
        _didCommit = true;
        // Re-based, so the Verify button for this channel goes away: the typed
        // value and the account's now agree.
        _user = updated;
        _emailController.text = updated.email ?? "";
        _phone = updated.phone ?? "";
        _step = _Step.details;
        _pendingChannel = null;
        _pendingValue = null;
        _debugOtp = null;
      });
      // Names the value that is now on the account, and only that one. The
      // old number is gone from this sheet by here — the fields were re-based
      // above — and repeating it in the confirmation would leave the reader
      // working out which of the two they now log in with.
      gShowSnack(
        context,
        channel == kContactChannelPhone
            ? "Your mobile number is now ${updated.phone ?? ''}"
            : "Your email address is now ${updated.email ?? ''}",
      );
    } on GB_ApiException catch (error) {
      // A wrong code says how many tries are left; an expired one says to ask
      // again; a 409 means somebody took the address while the code was out.
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _codeError = error.message;
      });
    }
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Padding(
      // viewInsets, not viewPadding: this is the keyboard's height, and it is
      // what the sheet has to clear while typing.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The grab handle from the design's sheets.
            Center(
              child: Container(
                width: 32.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: kHomeNavBorderColor,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 20.0),
            if (_step == _Step.details) ..._buildDetailsStep() else ..._buildCodeStep(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDetailsStep() {
    final double screenWidth = MediaQuery.of(context).size.width;

    return [
      const Text(
        "Edit your details",
        style: TextStyle(
          fontSize: kClassAppBarTitleSize,
          fontWeight: FontWeight.w500,
          color: kHomeTitleTextColor,
        ),
      ),
      const SizedBox(height: 6.0),
      const Text(
        "Your name saves straight away. A new email or number has to be "
        "verified first, because it is what you sign in with.",
        style: TextStyle(
          fontSize: kEventSubtitleTextSize,
          color: kHomeSubtitleTextColor,
        ),
      ),
      const SizedBox(height: 20.0),
      TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        enabled: !_isBusy,
        // Cleared on change rather than re-validated: the message is about what
        // was submitted, so it should go the moment the user starts fixing it.
        onChanged: (_) => setState(() => _nameError = null),
        decoration: _fieldDecoration(label: "Full name", error: _nameError),
      ),
      const SizedBox(height: 16.0),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        enabled: !_isBusy,
        onChanged: (_) => setState(() => _emailError = null),
        decoration: _fieldDecoration(
          label: "Email address",
          error: _emailError,
        ),
      ),
      if (_emailChanged)
        _buildVerifyPrompt(
          explanation:
              "We'll email a code to this address. Your current address keeps "
              "working until the code comes back.",
        ),
      const SizedBox(height: 16.0),
      // The same picker as phone login, so the number is saved in the form OTP
      // login looks it up by. A bare "9876543210" here would make logging in by
      // phone create a second account.
      //
      // initialValue carries the country code and initialCountryCode is left
      // off on purpose: given a "+..." number and no country, the field works
      // out which country that is. Hard-coding 'IN' would show a teacher with a
      // foreign number the wrong flag.
      //
      // Keyed on the committed number so that a successful verify rebuilds the
      // field against its new initialValue — without the key, Flutter reuses
      // the old state and the field keeps showing what was typed rather than
      // what was saved.
      IntlPhoneField(
        key: ValueKey<String>("phone-${_user.phone ?? ""}"),
        initialValue: (_user.phone ?? "").isEmpty ? null : _user.phone,
        initialCountryCode: (_user.phone ?? "").isEmpty ? "IN" : null,
        enabled: !_isBusy,
        decoration: _fieldDecoration(
          label: "Mobile number",
          error: _phoneError,
        ),
        onChanged: (value) {
          setState(() {
            _phone = value.completeNumber;
            _phoneError = null;
          });
        },
      ),
      if (_phoneChanged)
        _buildVerifyPrompt(
          explanation:
              "We'll text a code to this number. Your current number keeps "
              "working until the code comes back.",
        ),
      const SizedBox(height: 24.0),
      // GB_ElevatedButtonString sizes itself from its text plus a screenWidth
      // fraction, so it is stretched here rather than given a padding fraction
      // that would only be right on one screen width.
      SizedBox(
        width: double.infinity,
        child: GB_ElevatedButtonString(
          screenWidth: screenWidth,
          horizontalPadding: 0.0,
          verticalPadding: kElevatedButtonVerticalPadding,
          // The button says what it is about to do, and a changed contact is
          // the thing that needs doing — a sheet offering "Done" over an
          // unverified number would be claiming the edit was finished.
          elevatedButtonText: _primaryLabel,
          buttonColor: kHomeAccentColor,
          elevatedButtonTextColor: kPrimaryColor2,
          elevatedButtonFontWeight: FontWeight.w500,
          elevatedButtonTextSize: kElevatedButtonTextSize,
          onPressed: _isBusy ? null : _onPrimaryPressed,
        ),
      ),
    ];
  }

  /// The "option to verify" that appears under a contact the moment it stops
  /// matching the account — and the sentence saying the old one still works
  /// until it is used.
  Widget _buildVerifyPrompt({required String explanation}) {
    return Container(
      margin: const EdgeInsets.only(top: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: kClassTileYellowFill,
        border: Border.all(color: kClassTileYellowBorder),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18.0, color: kHomeIconColor),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  explanation,
                  style: const TextStyle(
                    fontSize: kClassSubtitleTextSize,
                    color: kHomeTitleTextColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCodeStep() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isPhone = _pendingChannel == kContactChannelPhone;

    // Pinput's own default cell, restated so the digits can be made larger —
    // the same theme GB_Verify uses, so a code looks like a code everywhere.
    final PinTheme defaultPinTheme = PinTheme(
      width: 48.0,
      height: 56.0,
      textStyle: const TextStyle(
        fontSize: kOtpDigitTextSize,
        color: kTextColor,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(222, 231, 240, .57),
        borderRadius: BorderRadius.circular(8.0),
      ),
    );

    return [
      Row(
        children: [
          // Back to the fields, not out of the sheet: the code is still valid
          // and the number may just need a digit fixed.
          IconButton(
            onPressed: _isBusy
                ? null
                : () => setState(() => _step = _Step.details),
            icon: const Icon(Icons.arrow_back, color: kHomeIconColor),
            tooltip: "Back to your details",
          ),
          const Expanded(
            child: Text(
              "Enter the code",
              style: TextStyle(
                fontSize: kClassAppBarTitleSize,
                fontWeight: FontWeight.w500,
                color: kHomeTitleTextColor,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6.0),
      Text(
        isPhone
            ? "We sent a 6-digit code to ${_pendingValue ?? ""}. Your number "
                "changes once it is entered, and not before."
            : "We sent a 6-digit code to ${_pendingValue ?? ""}. Your email "
                "changes once it is entered, and not before.",
        style: const TextStyle(
          fontSize: kEventSubtitleTextSize,
          color: kHomeSubtitleTextColor,
        ),
      ),
      const SizedBox(height: 20.0),
      Center(
        child: Pinput(
          controller: _codeController,
          length: 6,
          defaultPinTheme: defaultPinTheme,
          enabled: !_isVerifying,
          onCompleted: (_) => _verifyCode(),
        ),
      ),
      if (_codeError != null) ...[
        const SizedBox(height: 12.0),
        Text(
          _codeError!,
          style: const TextStyle(
            fontSize: kClassSubtitleTextSize,
            color: Colors.redAccent,
          ),
        ),
      ],
      const SizedBox(height: 8.0),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _isBusy || _secondsUntilResend > 0
              ? null
              : () => _sendCode(_pendingChannel ?? kContactChannelPhone),
          style: TextButton.styleFrom(foregroundColor: kHomeAccentColor),
          child: Text(
            _secondsUntilResend > 0
                ? "Resend code in ${_secondsUntilResend}s"
                : "Resend code",
          ),
        ),
      ),
      const SizedBox(height: 16.0),
      SizedBox(
        width: double.infinity,
        child: GB_ElevatedButtonString(
          screenWidth: screenWidth,
          horizontalPadding: 0.0,
          verticalPadding: kElevatedButtonVerticalPadding,
          elevatedButtonText: _isVerifying ? "Verifying…" : "Verify and save",
          buttonColor: kHomeAccentColor,
          elevatedButtonTextColor: kPrimaryColor2,
          elevatedButtonFontWeight: FontWeight.w500,
          elevatedButtonTextSize: kElevatedButtonTextSize,
          onPressed: _isBusy ? null : _verifyCode,
        ),
      ),
      if (kDebugMode && _debugOtp != null) _buildDevCodeReadout(_debugOtp!),
    ];
  }

  /// The generated code, printed at the bottom of the sheet in **debug builds
  /// only**.
  ///
  /// Login says the same thing in a SnackBar, and so does this sheet — but a
  /// modal bottom sheet is painted over the SnackBar, so on this screen that is
  /// the one place it cannot be read. Until an SMS and an email provider exist,
  /// this code is the only way through the flow at all, so it needs somewhere
  /// it is certain to be visible.
  ///
  /// [kDebugMode] is the half of the guard a release build carries with it and a
  /// server setting cannot undo: `OTP_DEBUG_RETURN` left on in production would
  /// still not put a code on a real user's screen. Same reasoning as
  /// GB_OtpRequestResult.displayMessage, which is why the wording matches it.
  Widget _buildDevCodeReadout(String code) {
    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: kClassTileBlueFill,
        border: Border.all(color: kClassTileBlueBorder),
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report_outlined, size: 18.0, color: kHomeIconColor),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              "dev code: $code",
              style: const TextStyle(
                fontSize: kClassSubtitleTextSize,
                fontWeight: FontWeight.w500,
                color: kHomeTitleTextColor,
              ),
            ),
          ),
          // Tapping it fills the boxes, because reading six digits off one line
          // and typing them into another is the whole of what this flow costs a
          // developer today.
          TextButton(
            onPressed: _isVerifying
                ? null
                : () {
                    _codeController.text = code;
                    _verifyCode();
                  },
            style: TextButton.styleFrom(foregroundColor: kHomeAccentColor),
            child: const Text("Use it"),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String? error,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: error,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kClassTileRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kClassTileRadius),
        borderSide: const BorderSide(color: kHomeAccentColor),
      ),
      labelStyle: const TextStyle(color: kHomeSubtitleTextColor),
      floatingLabelStyle: const TextStyle(color: kHomeAccentColor),
    );
  }
}
