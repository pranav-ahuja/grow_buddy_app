import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

class DropDownTextFieldMenu extends StatelessWidget {
  const DropDownTextFieldMenu({
    super.key,
    required this.onAccountTypeChanged,
  });

  final ValueChanged<int> onAccountTypeChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
      enableFilter: true,
      hintText: "Type of account",
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50.0),
        ),
      ),
      dropdownMenuEntries: const [
        DropdownMenuEntry(value: "Teacher", label: "Teacher"),
        DropdownMenuEntry(value: "Student", label: "Student"),
      ],
      label: const Text("Account Type"),
      onSelected: (value) {
        if (value == "Teacher") {
          onAccountTypeChanged(accountTypeTeacher);
        } else if (value == "Student") {
          onAccountTypeChanged(accountTypeStudent);
        }
      },
    );
  }
}
