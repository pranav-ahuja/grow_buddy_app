import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The two small decisions a class asks of a teacher: are you sure you want to
/// delete this, and what should it be called.
///
/// Dialogs rather than sheets or routes: both are a single question with two
/// answers, and both are asked from on top of the list or screen the answer
/// changes, which the teacher should keep seeing behind them.

/// Confirms deleting a class, explaining what is about to be saved and lost.
///
/// Returns true only on an explicit "Delete". The count is spelt out because
/// the students go with the class, and "delete Nursery" reads very differently
/// once you know it means eighteen pupils.
Future<bool> gConfirmDeleteClass(
  BuildContext context, {
  required GB_ClassInfo classInfo,
  required int studentCount,
}) async {
  final String subject = studentCount == 0
      ? "This class has no students yet."
      : studentCount == 1
          ? "Its 1 student will be removed with it."
          : "Its $studentCount students will be removed with it.";

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: kPrimaryColor2,
      title: Text('Delete "${classInfo.name}"?'),
      titleTextStyle: const TextStyle(
        fontSize: kClassAppBarTitleSize,
        fontWeight: FontWeight.w500,
        color: kHomeTitleTextColor,
      ),
      content: Text(
        "$subject\n\n"
        "You'll be asked where to save a class file first. Upload that file "
        "from \"Add a class\" to get everything back.",
        style: const TextStyle(
          fontSize: kEventSubtitleTextSize,
          height: 1.4,
          color: kHomeSubtitleTextColor,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: kHomeSubtitleTextColor),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text("Save and delete"),
        ),
      ],
    ),
  );

  // Null is a dismissal — tapping outside the dialog is not consent to delete.
  return confirmed ?? false;
}

/// Asks for a new name for [classInfo] and applies it.
///
/// Returns the renamed class, or null if the teacher cancelled or changed
/// nothing. The rename happens here rather than at the call site so the same
/// duplicate rule the add form enforces cannot be forgotten by a second caller.
Future<GB_ClassInfo?> gEditClassName(
  BuildContext context, {
  required GB_ClassInfo classInfo,
}) {
  return showDialog<GB_ClassInfo>(
    context: context,
    builder: (BuildContext context) => _GB_EditClassNameDialog(
      classInfo: classInfo,
    ),
  );
}

class _GB_EditClassNameDialog extends StatefulWidget {
  const _GB_EditClassNameDialog({required this.classInfo});

  final GB_ClassInfo classInfo;

  @override
  State<_GB_EditClassNameDialog> createState() =>
      _GB_EditClassNameDialogState();
}

class _GB_EditClassNameDialogState extends State<_GB_EditClassNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.classInfo.name);

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _controller.text.trim();

    if (name.isEmpty) {
      setState(() => _error = "Please enter a class name");
      return;
    }

    // ignoreId, so keeping the current name and pressing Save is not reported
    // as a clash with the class being renamed.
    if (GB_ClassStore.nameExists(name, ignoreId: widget.classInfo.id)) {
      setState(() => _error = "A class called \"$name\" already exists");
      return;
    }

    Navigator.of(context).pop(
      GB_ClassStore.renameClass(widget.classInfo.id, name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kPrimaryColor2,
      title: const Text("Edit class"),
      titleTextStyle: const TextStyle(
        fontSize: kClassAppBarTitleSize,
        fontWeight: FontWeight.w500,
        color: kHomeTitleTextColor,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        // The message is about what was submitted, so it goes the moment the
        // teacher starts fixing it.
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: "Class name",
          errorText: _error,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kClassTileRadius),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kClassTileRadius),
            borderSide: const BorderSide(color: kHomeAccentColor),
          ),
          labelStyle: const TextStyle(color: kHomeSubtitleTextColor),
          floatingLabelStyle: const TextStyle(color: kHomeAccentColor),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: kHomeSubtitleTextColor),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: _save,
          style: TextButton.styleFrom(foregroundColor: kHomeAccentColor),
          child: const Text("Save"),
        ),
      ],
    );
  }
}
