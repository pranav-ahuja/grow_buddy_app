import 'package:flutter/material.dart';

class GB_TextButton extends StatelessWidget {
  const GB_TextButton({
    super.key,
    required this.textButtonText,
    required this.textButtonColor,
    required this.onPressed,
  });

  final String textButtonText;
  final Color textButtonColor;
  final onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        textButtonText,
        style: TextStyle(
          color: textButtonColor,
        ),
      ),
    );
  }
}
