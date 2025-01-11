import 'package:flutter/material.dart';

class GB_SignUp extends StatefulWidget {
  const GB_SignUp({super.key});

  @override
  State<GB_SignUp> createState() => _GB_SignUpState();
}

class _GB_SignUpState extends State<GB_SignUp> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sign up"),
      ),
    );
  }
}
