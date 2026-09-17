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
      // Built from kAccountTypeOptions rather than listed here, so a role
      // added there appears on every picker at once.
      dropdownMenuEntries: [
        for (final GB_AccountTypeOption option in kAccountTypeOptions)
          DropdownMenuEntry<String>(
            value: option.label,
            label: option.label,
            leadingIcon: Icon(option.icon),
          ),
      ],
      label: const Text("Account Type"),
      onSelected: (value) {
        for (final GB_AccountTypeOption option in kAccountTypeOptions) {
          if (option.label == value) {
            onAccountTypeChanged(option.value);
            return;
          }
        }
      },
    );
  }
}
