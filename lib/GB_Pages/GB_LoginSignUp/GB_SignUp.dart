import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_Login.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:colorful_iconify_flutter/icons/logos.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:iconify_flutter/icons/material_symbols.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

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
  IconData passwordVisibilityIcon = Icons.visibility;

  bool confirmPasswordCloseButtonPressed = false;
  IconData confirmPasswordVisibilityIcon = Icons.visibility;

  int accountType = 0;

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
                            if (passwordCloseButtonPressed) {
                              passwordVisibilityIcon = Icons.visibility_off;
                            } else {
                              passwordVisibilityIcon = Icons.visibility;
                            }
                          });
                        },
                        textFieldLabel: "Password",
                        textFieldOnChanged: (value) {
                          password = value;
                        },
                        textFieldKeyboardType: TextInputType.visiblePassword,
                        textFieldObscureText: passwordCloseButtonPressed,
                      ),
                      GB_buildTextField(
                        controller: _confirmPasswordController,
                        suffixIcon: confirmPasswordVisibilityIcon,
                        iconAction: () {
                          setState(() {
                            confirmPasswordCloseButtonPressed =
                                !confirmPasswordCloseButtonPressed;
                            if (confirmPasswordCloseButtonPressed) {
                              confirmPasswordVisibilityIcon =
                                  Icons.visibility_off;
                            } else {
                              confirmPasswordVisibilityIcon = Icons.visibility;
                            }
                          });
                        },
                        textFieldLabel: "Confirm Password",
                        textFieldOnChanged: (value) {
                          confirmPassword = value;
                        },
                        textFieldKeyboardType: TextInputType.visiblePassword,
                        textFieldObscureText: confirmPasswordCloseButtonPressed,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: DropdownMenu<String>(
                          enableFilter: true,
                          hintText: "Type of account",
                          inputDecorationTheme: InputDecorationTheme(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50.0),
                              borderSide: BorderSide(
                                width: 1000.0,
                              ),
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
                          horizontalPadding: 0.3,
                          verticalPadding: 10.0,
                          elevatedButtonText: "Sign up",
                          buttonColor: kPrimaryColor1,
                          elevatedButtonTextColor: kPrimaryColor2,
                          elevatedButtonFontWeight: FontWeight.w500,
                          elevatedButtonTextSize: kElevatedButtonTextSize,
                          onPressed: () {
                            print("Account Type = $accountType");
                          },
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
                                    onPressed: () {},
                                  ),
                                  GB_ElevatedButtonIcons(
                                    elevatedButtonIcon: MaterialSymbols.call,
                                    elevatedButtonIconSize:
                                        kElevatedButtonIconSize,
                                    elevatedButtonPadding:
                                        kEvelatedButtonPadding,
                                    onPressed: () {},
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
