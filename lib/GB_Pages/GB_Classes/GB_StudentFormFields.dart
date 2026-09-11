import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The pieces the register-student sheet is built from.
///
/// They live here rather than inside the sheet because the sheet is already a
/// long form, and because the same outlined field and pill button are what the
/// design uses on every sheet — the next one to be built should reuse these
/// rather than restyle a bare [TextFormField].
///
/// Styling comes from the Figma frame `360-44515`: a 4pt-radius outline in
/// rgba(90,73,3,0.5), a 12pt floating label, and 16pt input text.

/// One outlined text field, matching the design's "Text Fields/Light".
///
/// [isRequired] only draws the asterisk; the validation itself stays with the
/// caller, because what makes a field valid differs per field (a name is
/// non-empty, an age is a plausible number) and the field should not have to
/// know.
class GB_SheetTextField extends StatelessWidget {
  const GB_SheetTextField({
    super.key,
    required this.controller,
    required this.label,
    this.isRequired = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLines = 1,
    this.validator,
    this.onTap,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  /// Makes the field a button that opens a picker, like the date of birth:
  /// read-only, no keyboard, and [onTap] runs instead of typing.
  final VoidCallback? onTap;

  final IconData? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: validator,
      readOnly: onTap != null,
      onTap: onTap,
      style: const TextStyle(
        fontSize: kFieldInputTextSize,
        height: 24.0 / kFieldInputTextSize,
        letterSpacing: 0.5,
        color: kHomeTitleTextColor,
      ),
      decoration: InputDecoration(
        // The asterisk rather than a "(required)" suffix: the design has no
        // room for the longer form beside a 140pt half-width field.
        labelText: isRequired ? "$label *" : label,
        suffixIcon: suffixIcon == null
            ? null
            : Icon(suffixIcon, color: kHomeSubtitleTextColor),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 16.0,
        ),
        // Flutter floats the label at 0.75x, so a 16pt resting label lands on
        // the design's 12pt floating one without a second style being needed.
        labelStyle: const TextStyle(
          fontSize: kFieldInputTextSize,
          color: kHomeSubtitleTextColor,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: kFieldInputTextSize,
          letterSpacing: 0.4,
          color: kHomeTitleTextColor,
        ),
        border: _outline(kFieldBorderColor),
        enabledBorder: _outline(kFieldBorderColor),
        focusedBorder: _outline(kHomeAccentColor),
      ),
    );
  }

  OutlineInputBorder _outline(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(kFieldRadius),
      borderSide: BorderSide(color: color),
    );
  }
}

/// The design's gender choice: two outlined boxes with a radio glyph, sized and
/// spaced like the two half-width fields directly above them.
///
/// Built from boxes rather than Material's [RadioListTile] so it lines up with
/// the fields it sits between — a stock radio tile is a different height and
/// carries no outline, and the row would visibly break the grid.
class GB_GenderSelector extends StatelessWidget {
  const GB_GenderSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final List<String> options;

  /// Null until the teacher picks one, which is what makes the field invalid.
  final String? selected;
  final ValueChanged<String> onChanged;

  /// Shown beneath the row, styled like a [TextFormField]'s own error so the
  /// gender row fails the same way the text fields around it do.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (int index = 0; index < options.length; index++) ...[
              if (index > 0) const SizedBox(width: kFieldRowGap),
              Expanded(child: _buildOption(options[index])),
            ],
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 12.0),
            child: Text(
              errorText!,
              style: TextStyle(
                fontSize: kFieldLabelTextSize,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOption(String option) {
    final bool isSelected = option == selected;

    return InkWell(
      onTap: () => onChanged(option),
      borderRadius: BorderRadius.circular(kFieldRadius),
      child: Container(
        height: 56.0,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kFieldRadius),
          border: Border.all(
            color: isSelected ? kHomeAccentColor : kFieldBorderColor,
            // Thickened rather than filled: a filled box at this size reads as
            // a button, and the design keeps every box in the grid outlined.
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20.0,
              color: isSelected ? kHomeAccentColor : kFieldBorderColor,
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                option,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: kFieldInputTextSize,
                  height: 24.0 / kFieldInputTextSize,
                  letterSpacing: 0.5,
                  color: kHomeTitleTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A heading over one block of the form ("Mother's details" and friends).
///
/// The form asks for four groups of fields; without these the teacher would be
/// scrolling an undifferentiated stack of twelve outlined boxes and guessing
/// whose mobile number a "Mobile" field wants.
class GB_SheetSectionHeader extends StatelessWidget {
  const GB_SheetSectionHeader({
    super.key,
    required this.title,
    this.isOptional = false,
  });

  final String title;

  /// Draws "Optional" beside the title, so the teacher can see at a glance that
  /// a whole block can be skipped rather than working that out field by field.
  final bool isOptional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: kSheetSectionTextSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
            color: kHomeTitleTextColor,
          ),
        ),
        if (isOptional) ...[
          const SizedBox(width: 8.0),
          const Text(
            "Optional",
            style: TextStyle(
              fontSize: kFieldLabelTextSize,
              color: kHomeSubtitleTextColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// The circular photo at the top of the sheet, tapped to pick one.
///
/// Shows the picked file when there is one and a camera prompt when there is
/// not, rather than a stock avatar: an empty ring with an icon says "add a
/// photo", where a stand-in face looks like a photo has already been chosen.
class GB_StudentPhotoPicker extends StatelessWidget {
  const GB_StudentPhotoPicker({
    super.key,
    required this.photoPath,
    required this.onTap,
  });

  final String? photoPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: kRegisterAvatarRadius * 2,
            height: kRegisterAvatarRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSheetGradientTopColor,
              border: Border.all(color: kFieldBorderColor),
              image: photoPath == null
                  ? null
                  : DecorationImage(
                      image: FileImage(File(photoPath!)),
                      fit: BoxFit.cover,
                    ),
            ),
            child: photoPath == null
                ? const Icon(
                    Icons.add_a_photo_outlined,
                    color: kHomeAccentColor,
                    size: 28.0,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8.0),
        Text(
          photoPath == null ? "Add photo" : "Change photo",
          style: const TextStyle(
            fontSize: kFieldLabelTextSize,
            color: kHomeAccentColor,
          ),
        ),
      ],
    );
  }
}

/// The design's rounded action button — a 100pt-radius pill in the accent
/// colour, wrapping its label rather than filling the row.
class GB_PillButton extends StatelessWidget {
  const GB_PillButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;

  /// Null disables the button, which is how the sheet blocks a second tap while
  /// a registration is in flight.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: kHomeAccentColor,
        foregroundColor: kPrimaryColor2,
        disabledBackgroundColor: kHomeAccentColor.withValues(alpha: 0.5),
        disabledForegroundColor: kPrimaryColor2,
        elevation: 0.0,
        padding: const EdgeInsets.symmetric(
          horizontal: kPillButtonHorizontalPadding,
          vertical: kPillButtonVerticalPadding,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kPillButtonRadius),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: kPillButtonTextSize,
          height: 20.0 / kPillButtonTextSize,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
