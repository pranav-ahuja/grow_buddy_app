import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

class DropDownTextFieldMenu extends StatelessWidget {
  DropDownTextFieldMenu({
    super.key,
    required this.accountType,
  });

  late int accountType;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
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
        DropdownMenuEntry(value: "Teacher", label: "Teacher"),
        DropdownMenuEntry(value: "Student", label: "Student"),
      ],
      label: Text("Account Type"),
      onSelected: (value) {
        if (value == "Teacher") {
          accountType = accountTypeTeacher;
        } else if (value == "Student") {
          accountType = accountTypeStudent;
        }
      },
    );
  }

  int get getAccountType => accountType;
}
