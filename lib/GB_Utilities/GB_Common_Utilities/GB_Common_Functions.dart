import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

Padding GB_buildTextField(
    {required TextEditingController controller,
    required IconData suffixIcon,
    required void Function() iconAction,
    String textFieldHintText = "",
    required String textFieldLabel,
    required void Function(String)? textFieldOnChanged,
    required TextInputType textFieldKeyboardType,
    bool textFieldObscureText = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10.0),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        suffixIcon: InkWell(
          child: Icon(
            suffixIcon,
          ),
          onTap: iconAction,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50.0),
        ),
        hintText: textFieldHintText,
        label: Text(textFieldLabel),
      ),
      keyboardType: textFieldKeyboardType,
      onChanged: textFieldOnChanged,
      obscureText: (textFieldLabel == "Password") &&
              (textFieldLabel == "Confirm Password")
          ? !textFieldObscureText
          : textFieldObscureText,
    ),
  );
}
