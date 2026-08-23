import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// Placeholder for the settings screen reached from the profile menu.
///
/// It exists so the menu item has somewhere real to go; the contents are not
/// designed yet. Unlike the home screens this one keeps its back arrow, since
/// it is pushed on top of the dashboard rather than replacing it.
class GB_Settings extends StatelessWidget {
  const GB_Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: AppBar(
        backgroundColor: kPrimaryColor2,
        surfaceTintColor: kPrimaryColor2,
        elevation: 0.0,
        centerTitle: true,
        title: const GB_AppBarText(
          appBarText: "Settings",
          appBarFontWeight: FontWeight.w500,
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.settings_outlined,
                size: 64.0,
                color: kHomeIconColor,
              ),
              SizedBox(height: 16.0),
              GB_H1HeadingText(
                inputText: "Settings",
                inputTextAlign: TextAlign.center,
              ),
              SizedBox(height: 8.0),
              GB_H2HeadingText(
                inputText: "Nothing to configure here yet.",
                inputTextAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
