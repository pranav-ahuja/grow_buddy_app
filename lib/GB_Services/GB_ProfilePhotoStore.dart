import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where a user's profile picture lives on this device.
///
/// **Device-local, and deliberately so for now.** There is no column on
/// `users` to put this in: the backend's `create_schema()` only creates tables
/// that are missing and never alters one that exists, so adding
/// `users.photo_path` needs Alembic, which the project has not set up yet. The
/// same limitation already applies to a student's photo, whose `photo_path` is
/// documented as "a path on the device that picked the photo". So a teacher
/// who signs in on a second phone sees their initials again until this moves
/// server-side.
///
/// Keyed by user id rather than stored under one key, so two accounts sharing
/// a device never inherit each other's picture, and so signing back in gets
/// yours back rather than a blank avatar.
///
/// `flutter_secure_storage` rather than a new `shared_preferences` dependency:
/// the Keystore is already wired up for the session, and one more small string
/// does not justify a second storage plugin. Nothing here is secret; this is
/// reuse, not a security claim.
class GB_ProfilePhotoStore {
  const GB_ProfilePhotoStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _keyFor(String userId) => "gb_profile_photo_$userId";

  /// The picture the profile screen is currently drawing, or null for initials.
  ///
  /// A [ValueNotifier] for the same reason the class and student stores are
  /// ones: the avatar has to repaint the moment a new photo is picked, and the
  /// project uses `ValueListenableBuilder` rather than a state-management
  /// package.
  static final ValueNotifier<String?> photoPath = ValueNotifier<String?>(null);

  /// Reads this user's picture into [photoPath].
  ///
  /// A path whose file has since gone — the teacher deleted it from their
  /// gallery, or the OS cleared a cache directory — is treated as no picture
  /// and forgotten, so the avatar falls back to initials instead of showing a
  /// broken box on every visit.
  static Future<void> load(String userId) async {
    final String? stored = await _read(userId);

    if (stored != null && !File(stored).existsSync()) {
      await clearFor(userId);
      return;
    }

    photoPath.value = stored;
  }

  static Future<void> save({
    required String userId,
    required String path,
  }) async {
    photoPath.value = path;
    try {
      await _storage.write(key: _keyFor(userId), value: path);
    } catch (error) {
      // A device that cannot persist still shows the picture for this run —
      // the notifier is already set. Not worth failing the pick over.
      debugPrint("[GB_ProfilePhotoStore] could not save photo: $error");
    }
  }

  /// Forgets this user's picture, on "Remove photo".
  static Future<void> clearFor(String userId) async {
    photoPath.value = null;
    try {
      await _storage.delete(key: _keyFor(userId));
    } catch (error) {
      debugPrint("[GB_ProfilePhotoStore] could not remove photo: $error");
    }
  }

  /// Drops the in-memory copy without forgetting what is on disk.
  ///
  /// For sign-out: the next account to use this device must not inherit the
  /// previous one's avatar, but the stored path is keyed by user id and stays,
  /// so the original owner gets their picture back when they sign in again.
  static void forget() {
    photoPath.value = null;
  }

  static Future<String?> _read(String userId) async {
    try {
      return await _storage.read(key: _keyFor(userId));
    } catch (error) {
      debugPrint("[GB_ProfilePhotoStore] could not read photo: $error");
      return null;
    }
  }

  /// Puts the store back to a freshly-launched state, so one test's photo
  /// cannot leak into the next.
  @visibleForTesting
  static void resetForTest() => forget();
}
