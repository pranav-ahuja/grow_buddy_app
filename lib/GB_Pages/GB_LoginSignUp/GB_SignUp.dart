import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_AuthApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:colorful_iconify_flutter/icons/logos.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:iconify_flutter/icons/material_symbols.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_MobileLogin.dart';

class GB_SignUp extends StatefulWidget {
  const GB_SignUp({super.key});

  @override
  State<GB_SignUp> createState() => _GB_SignUpState();
}

class _GB_SignUpState extends State<GB_SignUp> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailPhoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String fullName = "";
  String emailID_phoneNum = "";
  String password = "";
  String confirmPassword = "";

  bool passwordCloseButtonPressed = false;
  IconData passwordVisibilityIcon = Icons.visibility_off;

  bool confirmPasswordCloseButtonPressed = false;
  IconData confirmPasswordVisibilityIcon = Icons.visibility_off;

  // Null until the user actually picks one, so nobody is silently registered
  // as a teacher just because that constant happens to be 0.
  int? accountType;

  bool isSubmitting = false;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _signUp() async {
    if (fullName.trim().isEmpty) {
      _showSnack("Please enter your full name");
      return;
    }
    if (emailID_phoneNum.trim().isEmpty) {
      _showSnack("Please enter your email id or phone number");
      return;
    }
    if (password.length < 8) {
      _showSnack("Password must be at least 8 characters");
      return;
    }
    if (password != confirmPassword) {
      _showSnack("Passwords do not match");
      return;
    }
    if (accountType == null) {
      _showSnack("Please choose an account type");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final result = await GB_AuthApi.signUp(
        fullName: fullName.trim(),
        identifier: emailID_phoneNum.trim(),
        password: password,
        accountType: accountType!,
      );

      if (!mounted) return;
      // Sets the session and picks the destination from needsAccountType. A
      // password sign-up already chose a role, so this lands on the dashboard.
      gRouteAfterAuth(context, result);
    } on GB_ApiException catch (error) {
      _showSnack(error.message);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: GB_AppBarText(
          appBarFontWeight: FontWeight.w500,
          appBarText: "Sign up",
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GB_H1HeadingText(
                  inputText: "Join the Grow Buddy Community!",
                  inputTextAlign: TextAlign.center,
                ),
                GB_H2HeadingText(
                  inputText:
                      "Let's make managing your classroom a breeze. Create your account in just a few steps.",
                  inputTextAlign: TextAlign.center,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GB_buildTextField(
                        controller: _fullNameController,
                        suffixIcon: Icons.cancel_outlined,
                        iconAction: () {
                          setState(() {
                            _fullNameController.clear();
                          });
                        },
                        textFieldLabel: "Full Name",
                        textFieldOnChanged: (value) {
                          fullName = value;
                        },
                        textFieldKeyboardType: TextInputType.name,
                      ),
                      GB_buildTextField(
                        controller: _emailPhoneController,
                        suffixIcon: Icons.cancel_outlined,
                        iconAction: () {
                          setState(() {
                            _emailPhoneController.clear();
                          });
                        },
                        textFieldLabel: "Email id / Phone Number",
                        textFieldOnChanged: (value) {
                          emailID_phoneNum = value;
                        },
                        textFieldKeyboardType: TextInputType.emailAddress,
                      ),
                      GB_buildTextField(
                        controller: _passwordController,
                        suffixIcon: passwordVisibilityIcon,
                        iconAction: () {
                          setState(() {
                            passwordCloseButtonPressed =
                                !passwordCloseButtonPressed;
                            passwordVisibilityIcon = passwordCloseButtonPressed
                                ? Icons.visibility
                                : Icons.visibility_off;
                          });
                        },
                        textFieldLabel: "Password",
                        textFieldOnChanged: (value) {
                          password = value;
                        },
                        textFieldKeyboardType: TextInputType.visiblePassword,
                        textFieldObscureText: !passwordCloseButtonPressed,
                      ),
                      GB_buildTextField(
                        controller: _confirmPasswordController,
                        suffixIcon: confirmPasswordVisibilityIcon,
                        iconAction: () {
                          setState(() {
                            confirmPasswordCloseButtonPressed =
                                !confirmPasswordCloseButtonPressed;
                            confirmPasswordVisibilityIcon =
                                confirmPasswordCloseButtonPressed
                                    ? Icons.visibility
                                    : Icons.visibility_off;
                          });
                        },
                        textFieldLabel: "Confirm Password",
                        textFieldOnChanged: (value) {
                          confirmPassword = value;
                        },
                        textFieldKeyboardType: TextInputType.visiblePassword,
                        textFieldObscureText: !confirmPasswordCloseButtonPressed,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: DropdownMenu<String>(
                          enableFilter: true,
                          hintText: "Type of account",
                          inputDecorationTheme: InputDecorationTheme(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50.0),
                            ),
                          ),
                          dropdownMenuEntries: [
                            DropdownMenuEntry(
                                value: "Teacher", label: "Teacher"),
                            DropdownMenuEntry(
                                value: "Student", label: "Student"),
                          ],
                          label: Text("Account Type"),
                          onSelected: (value) {
                            if (value == "Teacher") {
                              accountType = accountTypeTeacher;
                            } else if (value == "Student") {
                              accountType = accountTypeStudent;
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: GB_ElevatedButtonString(
                          screenWidth: screenWidth,
                          horizontalPadding: 0.2,
                          verticalPadding: 10.0,
                          elevatedButtonText:
                              isSubmitting ? "Creating account..." : "Sign up",
                          buttonColor: kPrimaryColor1,
                          elevatedButtonTextColor: kPrimaryColor2,
                          elevatedButtonFontWeight: FontWeight.w500,
                          elevatedButtonTextSize: kElevatedButtonTextSize,
                          onPressed: isSubmitting ? null : _signUp,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GB_ElevatedButtonIcons(
                                    elevatedButtonIcon: Logos.google_icon,
                                    elevatedButtonIconSize:
                                        kElevatedButtonIconSize,
                                    elevatedButtonPadding:
                                        kEvelatedButtonPadding,
                                    onPressed: isSubmitting
                                        ? null
                                        : () => gSignInWithGoogle(context),
                                  ),
                                  GB_ElevatedButtonIcons(
                                    elevatedButtonIcon: MaterialSymbols.call,
                                    elevatedButtonIconSize:
                                        kElevatedButtonIconSize,
                                    elevatedButtonPadding:
                                        kEvelatedButtonPadding,
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              GB_MobileLogin(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: GB_TextButton(
                                textButtonText:
                                    "Already have an account? Login here",
                                textButtonColor: Colors.black87,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => GB_Login(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
