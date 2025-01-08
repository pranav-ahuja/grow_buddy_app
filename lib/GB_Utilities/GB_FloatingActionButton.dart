import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

class GB_FloatingActionButton extends StatelessWidget {
  const GB_FloatingActionButton({
    super.key,
    required this.floatingActionButtonIcon,
    required this.floatingActionButtonForegroundColor,
    required this.floatingActionButtonBackgroundColor,
    required this.onPressed,
  });

  final IconData floatingActionButtonIcon;
  final Color floatingActionButtonForegroundColor;
  final Color floatingActionButtonBackgroundColor;
  final onPressed;
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      child: Icon(
        floatingActionButtonIcon,
        color: floatingActionButtonForegroundColor,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kFloatingButtonCircularRadius),
        side: BorderSide(
          width: kFloatingButtonStrokeSize,
          color: floatingActionButtonForegroundColor,
        ),
      ),
      backgroundColor: floatingActionButtonBackgroundColor,
      splashColor: floatingActionButtonBackgroundColor,
    );
  }
}
