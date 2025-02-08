import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';

class GB_ElevatedButtonString extends StatelessWidget {
  GB_ElevatedButtonString({
    super.key,
    required this.screenWidth,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.elevatedButtonText,
    required this.buttonColor,
    required this.elevatedButtonTextColor,
    required this.elevatedButtonFontWeight,
    required this.elevatedButtonTextSize,
    required this.onPressed,
  });

  final double screenWidth;
  final double horizontalPadding;
  final double verticalPadding;
  final String elevatedButtonText;
  final Color buttonColor;
  final Color elevatedButtonTextColor;
  final double elevatedButtonTextSize;
  final FontWeight elevatedButtonFontWeight;
  final onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(buttonColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Text(
          elevatedButtonText,
          style: TextStyle(
            color: elevatedButtonTextColor,
            fontSize: elevatedButtonTextSize,
            fontWeight: elevatedButtonFontWeight,
          ),
        ),
      ),
    );
  }
}

class GB_ElevatedButtonIcons extends StatelessWidget {
  const GB_ElevatedButtonIcons({
    super.key,
    required this.elevatedButtonIcon,
    required this.elevatedButtonIconSize,
    required this.elevatedButtonPadding,
    required this.onPressed,
  });

  final double elevatedButtonPadding;
  final String elevatedButtonIcon;
  final double elevatedButtonIconSize;
  final onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          CircleBorder(),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(elevatedButtonPadding),
        child: Iconify(
          elevatedButtonIcon,
          size: elevatedButtonIconSize,
        ),
      ),
    );
  }
}
