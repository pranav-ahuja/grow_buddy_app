import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassArchive.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassArchiveFile.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Elevated_Buttons.dart';

/// The "add a class" form, shown as a bottom sheet from the dashboard.
///
/// A sheet rather than a pushed page because it asks for one field: pushing a
/// whole route to collect a class name would make adding a class feel heavier
/// than it is, and the teacher stays looking at the list they are adding to.
///
/// It is also where a deleted class comes back. Uploading the file that the
/// delete saved fills the sheet with that class's students, and the name is
/// still typed here — so restoring is the same one-field action as adding,
/// with a file attached, rather than a second screen that does almost the same
/// thing.
///
/// Call [show]; it returns the created class, or null if the teacher backed
/// out, so the caller can react (the dashboard confirms with a snackbar).
class GB_AddClassSheet extends StatefulWidget {
  const GB_AddClassSheet({super.key});

  static Future<GB_ClassInfo?> show(BuildContext context) {
    return showModalBottomSheet<GB_ClassInfo>(
      context: context,
      backgroundColor: kPrimaryColor2,
      // The keyboard would otherwise cover the field and the button; this lets
      // the sheet ride above it.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kClassPanelRadius),
        ),
      ),
      builder: (BuildContext context) => const GB_AddClassSheet(),
    );
  }

  @override
  State<GB_AddClassSheet> createState() => _GB_AddClassSheetState();
}

class _GB_AddClassSheetState extends State<GB_AddClassSheet> {
  final TextEditingController _nameController = TextEditingController();

  /// Shown under the field. Null while the input is acceptable.
  String? _error;

  /// The uploaded archive, once one has been read successfully. Null for an
  /// ordinary new class.
  GB_ClassArchiveData? _archive;

  /// What went wrong with the last upload, shown under the upload button.
  String? _archiveError;

  /// True while the file picker is open, so the upload cannot be started twice.
  bool _isReadingFile = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _uploadArchive() async {
    setState(() {
      _isReadingFile = true;
      _archiveError = null;
    });

    try {
      final Uint8List? bytes = await GB_ClassArchiveFile.pick();
      if (!mounted) return;

      // Null is a cancelled picker, which is not an error worth reporting.
      if (bytes == null) return;

      final GB_ClassArchiveData archive = GB_ClassArchive.decode(bytes);
      if (!mounted) return;

      setState(() {
        _archive = archive;
        // Offered, not imposed: the teacher names the restored class and can
        // still change it, but retyping a name the file already knows is busy
        // work when they are recovering from a mistake.
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = archive.className;
          _error = null;
        }
      });
    } on GB_ClassArchiveException catch (error) {
      if (!mounted) return;
      setState(() => _archiveError = error.message);
    } finally {
      if (mounted) setState(() => _isReadingFile = false);
    }
  }

  void _clearArchive() {
    setState(() {
      _archive = null;
      _archiveError = null;
    });
  }

  void _submit() {
    final String name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = "Please enter a class name");
      return;
    }

    // Checked rather than allowed-and-deduplicated later: two classes with the
    // same name are indistinguishable in the dashboard list, so the teacher
    // would have no way to tell which tile is which.
    if (GB_ClassStore.nameExists(name)) {
      setState(() => _error = "A class called \"$name\" already exists");
      return;
    }

    final GB_ClassInfo created = GB_ClassStore.addClass(name: name);

    // The students go in against the new class's id, so a restored class is
    // indistinguishable from one that was never deleted.
    final GB_ClassArchiveData? archive = _archive;
    if (archive != null && archive.students.isNotEmpty) {
      GB_StudentStore.restoreStudents(archive.students, classId: created.id);
    }

    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final GB_ClassArchiveData? archive = _archive;

    return Padding(
      // viewInsets, not viewPadding: this is the keyboard's height, and it is
      // what the sheet has to clear while typing.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The grab handle from the design's sheets.
            Center(
              child: Container(
                width: 32.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: kHomeNavBorderColor,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 20.0),
            const Text(
              "Add a class",
              style: TextStyle(
                fontSize: kClassAppBarTitleSize,
                fontWeight: FontWeight.w500,
                color: kHomeTitleTextColor,
              ),
            ),
            const SizedBox(height: 6.0),
            const Text(
              "It will show up on your dashboard straight away.",
              style: TextStyle(
                fontSize: kEventSubtitleTextSize,
                color: kHomeSubtitleTextColor,
              ),
            ),
            const SizedBox(height: 20.0),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              // Clearing on change rather than re-validating: the message is
              // about what was submitted, so it should go the moment the
              // teacher starts fixing it.
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: "Class name",
                hintText: "e.g. Nursery",
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
            if (archive == null) _buildUploadPrompt() else _buildArchiveSummary(archive),
            const SizedBox(height: 24.0),
            // GB_ElevatedButtonString sizes itself from its text plus a
            // screenWidth fraction, so it is stretched here rather than given a
            // padding fraction that would only be right on one screen width.
            SizedBox(
              width: double.infinity,
              child: GB_ElevatedButtonString(
                screenWidth: screenWidth,
                horizontalPadding: 0.0,
                verticalPadding: kElevatedButtonVerticalPadding,
                elevatedButtonText:
                    archive == null ? "Add class" : "Restore class",
                buttonColor: kHomeAccentColor,
                elevatedButtonTextColor: kPrimaryColor2,
                elevatedButtonFontWeight: FontWeight.w500,
                elevatedButtonTextSize: kElevatedButtonTextSize,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The "bring a deleted class back" affordance, shown until a file is loaded.
  Widget _buildUploadPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isReadingFile ? null : _uploadArchive,
            icon: _isReadingFile
                ? const SizedBox(
                    width: kFieldLabelTextSize,
                    height: kFieldLabelTextSize,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Icons.upload_file, size: kClassDeleteIconSize),
            label: Text(
              _isReadingFile ? "Reading…" : "Upload an existing class file",
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: kHomeAccentColor,
              side: const BorderSide(color: kHomeNavBorderColor),
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kClassTileRadius),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6.0),
        Text(
          _archiveError ??
              "Deleting a class saves a file. Upload it here to get the "
                  "class and its students back.",
          style: TextStyle(
            fontSize: kFieldLabelTextSize,
            height: 1.4,
            color: _archiveError == null
                ? kHomeSubtitleTextColor
                : Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }

  /// What was found in the uploaded file, and a way to back out of it.
  Widget _buildArchiveSummary(GB_ClassArchiveData archive) {
    final int count = archive.students.length;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: kClassTileGreenFill,
        borderRadius: BorderRadius.circular(kClassTileRadius),
        border: Border.all(color: kClassTileGreenBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            color: kHomeAccentColor,
            size: kClassDeleteIconSize,
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  archive.className.isEmpty
                      ? "Class file loaded"
                      : "${archive.className} loaded",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: kEventSubtitleTextSize,
                    fontWeight: FontWeight.w500,
                    color: kHomeTitleTextColor,
                  ),
                ),
                Text(
                  count == 0
                      ? "No students in the file"
                      : "$count ${count == 1 ? "student" : "students"} "
                          "will be restored",
                  style: const TextStyle(
                    fontSize: kFieldLabelTextSize,
                    color: kHomeSubtitleTextColor,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearArchive,
            icon: const Icon(Icons.close),
            color: kHomeSubtitleTextColor,
            iconSize: kClassDeleteIconSize,
            visualDensity: VisualDensity.compact,
            tooltip: "Remove this file",
          ),
        ],
      ),
    );
  }
}
