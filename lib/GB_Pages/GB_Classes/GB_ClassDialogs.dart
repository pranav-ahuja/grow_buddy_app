import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassWidgets.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The two small decisions a class asks of a teacher: are you sure you want to
/// delete this, and what should it be called and coloured.
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

/// Asks for a new name and theme colour for [classInfo] and applies them.
///
/// Returns the edited class, or null if the teacher cancelled. The edit happens
/// here rather than at the call site so the same duplicate rule the add form
/// enforces cannot be forgotten by a second caller.
Future<GB_ClassInfo?> gEditClass(
  BuildContext context, {
  required GB_ClassInfo classInfo,
}) {
  return showDialog<GB_ClassInfo>(
    context: context,
    builder: (BuildContext context) => _GB_EditClassDialog(
      classInfo: classInfo,
    ),
  );
}

class _GB_EditClassDialog extends StatefulWidget {
  const _GB_EditClassDialog({required this.classInfo});

  final GB_ClassInfo classInfo;

  @override
  State<_GB_EditClassDialog> createState() => _GB_EditClassDialogState();
}

class _GB_EditClassDialogState extends State<_GB_EditClassDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.classInfo.name);

  /// Opens on the colour the class already has, so the dialog shows the current
  /// state rather than asking the teacher to re-pick it to keep it.
  late int _colorSlot =
      GB_ClassPalette.slotForFill(widget.classInfo.fillColor);

  String? _error;

  /// True while the edit is with the server, so Save cannot send it twice.
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
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

    setState(() => _isSaving = true);

    try {
      // Both in one call: a name change and a colour change made on the same
      // form are one edit, and applying them separately would repaint the
      // dashboard twice and publish a half-edited class in between.
      final GB_ClassInfo edited = await GB_ClassStore.updateClass(
        widget.classInfo.id,
        name: name,
        colorSlot: _colorSlot,
      );
      if (!mounted) return;
      Navigator.of(context).pop(edited);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      // Kept open with the edit intact, so the teacher can fix the name or
      // retry rather than retyping it. A class deleted from another device
      // reports as not found here.
      setState(() {
        _error = error.message;
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kPrimaryColor2,
      // The dialog is now a field plus two rows of swatches, which on a short
      // screen with the keyboard up is taller than the space it is given.
      // Without this it would overflow rather than scroll.
      scrollable: true,
      title: const Text("Edit class"),
      titleTextStyle: const TextStyle(
        fontSize: kClassAppBarTitleSize,
        fontWeight: FontWeight.w500,
        color: kHomeTitleTextColor,
      ),
      // maxFinite, so the swatch row has a width to wrap inside — an
      // AlertDialog otherwise sizes its content to the widest child, and a Wrap
      // asked to lay out in unbounded width never wraps at all.
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              // The message is about what was submitted, so it goes the moment
              // the teacher starts fixing it.
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
            const SizedBox(height: 20.0),
            GB_ClassColorPicker(
              selectedSlot: _colorSlot,
              onSelected: (int slot) => setState(() => _colorSlot = slot),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: kHomeSubtitleTextColor),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: _isSaving ? null : _save,
          style: TextButton.styleFrom(foregroundColor: kHomeAccentColor),
          child: Text(_isSaving ? "Saving…" : "Save"),
        ),
      ],
    );
  }
}
