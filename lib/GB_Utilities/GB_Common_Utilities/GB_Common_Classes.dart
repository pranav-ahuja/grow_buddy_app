import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

class GB_H2HeadingText extends StatelessWidget {
  const GB_H2HeadingText({
    super.key,
    required this.inputText,
    required this.inputTextAlign,
  });

  final String inputText;
  final TextAlign inputTextAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      inputText,
      textAlign: inputTextAlign,
      style: kH2TextStyle,
    );
  }
}

class GB_H1HeadingText extends StatelessWidget {
  const GB_H1HeadingText({
    super.key,
    required this.inputText,
    required this.inputTextAlign,
  });

  final String inputText;
  final TextAlign inputTextAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      inputText,
      textAlign: inputTextAlign,
      style: kH1TextStyle,
    );
  }
}

class GB_AppBarText extends StatelessWidget {
  const GB_AppBarText({
    super.key,
    required this.appBarFontWeight,
    required this.appBarText,
  });

  final String appBarText;
  final FontWeight appBarFontWeight;

  @override
  Widget build(BuildContext context) {
    return Text(
      appBarText,
      style: TextStyle(
        fontWeight: appBarFontWeight,
      ),
    );
  }
}
