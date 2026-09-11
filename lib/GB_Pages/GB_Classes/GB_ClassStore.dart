import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';

/// This device's copy of the teacher's classes.
///
/// The classes themselves live on the server, against the signed-in account —
/// that is what makes the same login show the same classes on a phone and an
/// emulator. This store holds the copy the screens draw from, and every change
/// goes to the server first: the copy is only updated once the server has
/// accepted it, so it can never show a class that does not really exist.
///
/// A [ValueNotifier] rather than a plain list: the dashboard has to repaint the
/// moment a class is added, and this is the lightest way to say so without
/// pulling a state-management package into a project that has none. Screens
/// listen with a `ValueListenableBuilder`.
///
/// Another device's changes arrive on the next [load]. There is no push from
/// the server, so the dashboard reloads when it opens, when the app returns to
/// the foreground, and on pull-to-refresh.
class GB_ClassStore {
  const GB_ClassStore._();

  /// Starts empty and is filled by [load]. There is no seed: these are a real
  /// teacher's classes now, and five made-up ones would have to be deleted by
  /// hand before the list meant anything.
  static final ValueNotifier<List<GB_ClassInfo>> classes =
      ValueNotifier<List<GB_ClassInfo>>(<GB_ClassInfo>[]);

  /// Replaces the local copy with the server's.
  ///
  /// A replacement rather than a merge: the server's list is the truth, and a
  /// class deleted on another device has to disappear here too.
  static Future<void> load() async {
    classes.value = await GB_ClassApi.listClasses(token: gRequireToken());
  }

  /// The palette slot a class added right now would get if the teacher picks
  /// nothing — the next one along in the cycle, so consecutive classes do not
  /// all arrive the same colour.
  ///
  /// Exposed because the add form opens with this slot preselected, and it
  /// should not have to reproduce the rule to do so.
  static int get nextColorSlot => classes.value.length % GB_ClassPalette.length;

  /// Adds a class on the server and returns it as the server stored it.
  ///
  /// [colorSlot] is the palette slot the teacher picked. Null falls back to
  /// [nextColorSlot], so a caller that does not offer the choice still gets a
  /// coloured class rather than an uncoloured one.
  ///
  /// [students] is for "Restore class": the class file's students go up in the
  /// same request, and the server creates both or neither. They land in
  /// [GB_StudentStore] on its next load, not here.
  ///
  /// Throws [GB_ApiException] if the server refuses — a duplicate name added
  /// from another device, say — and leaves the local copy untouched.
  static Future<GB_ClassInfo> addClass({
    required String name,
    int? colorSlot,
    List<GB_Student> students = const [],
  }) async {
    final GB_ClassInfo created = await GB_ClassApi.createClass(
      token: gRequireToken(),
      name: name.trim(),
      colorSlot: colorSlot ?? nextColorSlot,
      students: students,
    );

    // A new list is assigned rather than the existing one mutated: ValueNotifier
    // compares with `==`, and mutating in place leaves the identical List
    // instance in the field, so no listener would be told anything changed.
    classes.value = [...classes.value, created];
    return created;
  }

  /// True when [name] is already taken, ignoring case and surrounding spaces —
  /// what the add form checks before letting a duplicate through.
  ///
  /// Only as current as the last [load], so the server checks again and has
  /// the final say. This is here so the common case — a name already on
  /// screen — is caught instantly instead of after a round trip.
  ///
  /// [ignoreId] excludes one class from the comparison, which is what the
  /// rename form needs: a class is allowed to keep its own name, so without
  /// this, saving the edit dialog unchanged would report a clash with itself.
  static bool nameExists(String name, {String? ignoreId}) {
    final String candidate = name.trim().toLowerCase();
    return classes.value.any(
      (GB_ClassInfo item) =>
          item.id != ignoreId && item.name.toLowerCase() == candidate,
    );
  }

  /// Changes a class's name, its colour, or both, and returns it in its new
  /// form.
  ///
  /// Both edits go through one request because "Edit class" asks for them on
  /// one form: applying them separately would publish a half-edited class to
  /// every listener in between, and repaint the dashboard twice for one Save.
  ///
  /// Omitting an argument leaves that part alone, so renaming cannot quietly
  /// reshuffle the class's tint, and recolouring cannot rename it.
  static Future<GB_ClassInfo> updateClass(
    String id, {
    String? name,
    int? colorSlot,
  }) async {
    final GB_ClassInfo edited = await GB_ClassApi.updateClass(
      token: gRequireToken(),
      id: id,
      name: name?.trim(),
      colorSlot: colorSlot,
    );

    classes.value = [
      for (final GB_ClassInfo item in classes.value)
        if (item.id == id) edited else item,
    ];
    return edited;
  }

  /// The class with [id], or null once it has been deleted.
  static GB_ClassInfo? byId(String id) {
    for (final GB_ClassInfo item in classes.value) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Deletes a class on the server — which deletes its students there too —
  /// and then drops it from the local copy.
  static Future<void> removeClass(String id) async {
    await GB_ClassApi.deleteClass(token: gRequireToken(), id: id);
    classes.value = classes.value
        .where((GB_ClassInfo item) => item.id != id)
        .toList();
  }

  /// Forgets the local copy — on sign-out, so the next account to sign in on
  /// this device does not briefly see the previous teacher's classes.
  static void clear() {
    classes.value = <GB_ClassInfo>[];
  }

  /// Puts the store back to a freshly-launched state.
  ///
  /// Static state outlives an individual test, so without this anything a
  /// previous test loaded would leak into the next one and make results depend
  /// on test order.
  @visibleForTesting
  static void resetForTest() => clear();
}
