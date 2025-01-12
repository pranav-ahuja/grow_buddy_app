import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_LoginSignUp/GB_SignUp.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_TextButton.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Functions.dart';

class GB_Login extends StatefulWidget {
  const GB_Login({super.key});

  @override
  State<GB_Login> createState() => _GB_LoginState();
}

class _GB_LoginState extends State<GB_Login> {
  final TextEditingController _email_controller = TextEditingController();
  final TextEditingController _password_controller = TextEditingController();

  String emailAddress = "";
  String password = "";
  bool emailCloseButtonPressed = false;
  bool passwordCloseButtonPressed = false;
  IconData passwordVisibilityIcon = Icons.visibility;

  bool isCheckBoxChecked = false;
  Color checkBoxColor = kPrimaryColor2;
  Color rememberMeColor = Colors.grey;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: GB_AppBarText(
          appBarText: "Login",
          appBarFontWeight: FontWeight.w500,
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/images/login_page.png"),
              GB_H1HeadingText(
                inputText: "Welcome back to Grow Buddy",
                inputTextAlign: TextAlign.center,
              ),
              GB_H2HeadingText(
                inputText:
                    "Manage your classroom, all in one place. Enter your email and password to continue.",
                inputTextAlign: TextAlign.center,
              ),
              Container(
                margin: EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    GB_buildTextField(
                      controller: _email_controller,
                      suffixIcon: Icons.cancel_outlined,
                      iconAction: () {
                        setState(() {
                          _email_controller.clear();
                        });
                      },
                      textFieldHintText: "abc@example.com",
                      textFieldLabel: "Email",
                      textFieldKeyboardType: TextInputType.emailAddress,
                      textFieldOnChanged: (value) {
                        emailAddress = value;
                      },
                    ),
                    GB_buildTextField(
                      controller: _password_controller,
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
                    Row(
                      children: [
                        Checkbox(
                          value: isCheckBoxChecked,
                          fillColor: MaterialStateProperty.all(checkBoxColor),
                          onChanged: (bool? newVal) {
                            setState(() {
                              isCheckBoxChecked = !isCheckBoxChecked;

                              checkBoxColor = isCheckBoxChecked
                                  ? kPrimaryColor1
                                  : kPrimaryColor2;
                              rememberMeColor = isCheckBoxChecked
                                  ? kPrimaryColor1
                                  : Colors.black54;
                            });
                          },
                        ),
                        GB_TextButton(
                          textButtonText: "Remember me",
                          textButtonColor: rememberMeColor,
                          textButtonTextSize: 18.0,
                          onPressed: () {
                            setState(() {
                              isCheckBoxChecked = !isCheckBoxChecked;
                              rememberMeColor = isCheckBoxChecked
                                  ? kPrimaryColor1
                                  : Colors.black45;
                              checkBoxColor = isCheckBoxChecked
                                  ? kPrimaryColor1
                                  : kPrimaryColor2;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GB_ElevatedButtonString(
                screenWidth: screenWidth,
                horizontalPadding: 0.35,
                verticalPadding: kElevatedButtonVerticalPadding,
                elevatedButtonText: "Login",
                buttonColor: kPrimaryColor1,
                elevatedButtonTextColor: kPrimaryColor2,
                elevatedButtonFontWeight: FontWeight.w500,
                elevatedButtonTextSize: kElevatedButtonTextSize,
                onPressed: () {},
              ),
              Container(
                height: 200.0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GB_TextButton(
                      onPressed: () {},
                      textButtonColor: Colors.black54,
                      textButtonText: "Forgot Password?",
                    ),
                    GB_TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GB_SignUp(),
                          ),
                        );
                      },
                      textButtonColor: Colors.black54,
                      textButtonText: "New to Grow Buddy? Sign up now",
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
