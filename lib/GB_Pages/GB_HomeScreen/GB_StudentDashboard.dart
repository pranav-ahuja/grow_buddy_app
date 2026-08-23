import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeAppBar.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Common_Classes.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// The student's home screen — not designed yet.
///
/// It shares [GB_HomeAppBar] with the teacher screen so a student still gets
/// the profile menu, and therefore a way to log out, while the body is pending.
class GB_StudentDashboard extends StatelessWidget {
  const GB_StudentDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final String name = gCurrentUser?.fullName ?? "there";

    return Scaffold(
      backgroundColor: kPrimaryColor2,
      appBar: const GB_HomeAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.school_outlined,
                size: 64.0,
                color: kPrimaryColor1,
              ),
              const SizedBox(height: 16.0),
              GB_H1HeadingText(
                inputText: "Hi $name!",
                inputTextAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              const GB_H2HeadingText(
                inputText: "Your dashboard is on its way.",
                inputTextAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
