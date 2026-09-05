import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// The save and open dialogs for a class archive.
///
/// Split from [GB_ClassArchive] so the workbook codec stays pure: everything
/// here talks to a platform channel and can only run on a device, while the
/// encoding either side of it can be tested outright.
///
/// The system dialogs are used rather than writing to the Downloads folder
/// directly. On Android 10 and up that folder is only reachable through
/// MediaStore or a broad "all files" permission, where the system picker needs
/// neither — and it lets the teacher put the file where they will find it.
class GB_ClassArchiveFile {
  const GB_ClassArchiveFile._();

  /// Offers [bytes] to the system save dialog and returns where it landed, or
  /// null if the teacher backed out.
  ///
  /// Callers must treat null as "do not delete the class" — the whole point of
  /// the export is that the class is recoverable, and it is not recoverable if
  /// the file was never written.
  static Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: "Save the class file",
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>["xlsx"],
        // Required on Android and iOS: there is no writable path to hand back,
        // so the plugin writes the bytes itself.
        bytes: bytes,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Asks the teacher for a class file and returns its bytes, or null if they
  /// backed out.
  static Future<Uint8List?> pick() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: "Choose a class file",
        type: FileType.custom,
        allowedExtensions: <String>["xlsx"],
        // Asks the plugin to read the file for us. On Android the picked file
        // often lives behind a content:// URI with no real path, so reading it
        // ourselves from `path` would fail for exactly the files the system
        // picker is most likely to return.
        withData: true,
      );

      if (result == null || result.files.isEmpty) return null;

      final PlatformFile file = result.files.first;
      if (file.bytes != null) return file.bytes;

      // Desktop platforms hand back a path instead of the bytes.
      final String? path = file.path;
      if (path == null) return null;
      return await File(path).readAsBytes();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
