import 'package:flutter/foundation.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The teacher's classes, and the only place they are mutated.
///
/// A [ValueNotifier] rather than a plain global list: the dashboard has to
/// repaint the moment a class is added, and this is the lightest way to say so
/// without pulling a state-management package into a project that has none.
/// Screens listen with a `ValueListenableBuilder`.
///
/// Everything here is in memory, so added classes are lost when the app is
/// killed. That is deliberate for now — there is no classes endpoint on the
/// backend yet. When there is, [addClass] becomes the POST and [load] the GET;
/// no caller needs to change, because they already read [classes] rather than
/// holding their own copy.
class GB_ClassStore {
  const GB_ClassStore._();

  /// Hands out ids. Starts past the seeded classes so a newly added class can
  /// never collide with one of them.
  static int _nextId = _seed.length;

  /// The five classes the design shows. Seeded so the dashboard is not empty
  /// on first run; a teacher can add to them.
  static const List<GB_ClassInfo> _seed = [
    GB_ClassInfo(
      id: 0,
      name: "Daycare",
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: kClassTileYellowFill,
      borderColor: kClassTileYellowBorder,
    ),
    GB_ClassInfo(
      id: 1,
      name: "Playgroup",
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: kClassTilePinkFill,
      borderColor: kClassTilePinkBorder,
    ),
    GB_ClassInfo(
      id: 2,
      name: "Pre Nursery",
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: kClassTileBlueFill,
      borderColor: kClassTileBlueBorder,
    ),
    GB_ClassInfo(
      id: 3,
      name: "Nursery",
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: kClassTileGreenFill,
      borderColor: kClassTileGreenBorder,
    ),
    GB_ClassInfo(
      id: 4,
      name: "KG",
      subtitle: "no. of students",
      imagePath: kClassAvatarImage,
      fillColor: kClassTilePurpleFill,
      borderColor: kClassTilePurpleBorder,
    ),
  ];

  /// The live list. Read it, do not mutate it — every write goes through the
  /// methods below so listeners actually fire.
  static final ValueNotifier<List<GB_ClassInfo>> classes =
      ValueNotifier<List<GB_ClassInfo>>(List<GB_ClassInfo>.from(_seed));

  /// Adds a class and returns it.
  ///
  /// The colour is chosen by position in the palette cycle, so the sixth class
  /// starts the five tints over rather than arriving uncoloured.
  ///
  /// A new list is assigned rather than the existing one mutated: ValueNotifier
  /// compares with `==`, and mutating in place leaves the identical List
  /// instance in the field, so no listener would be told anything changed.
  static GB_ClassInfo addClass({
    required String name,
    String subtitle = "no. of students",
  }) {
    final int slot = classes.value.length % GB_ClassPalette.length;

    final GB_ClassInfo created = GB_ClassInfo(
      id: _nextId++,
      name: name.trim(),
      subtitle: subtitle,
      imagePath: kClassAvatarImage,
      fillColor: GB_ClassPalette.fillAt(slot),
      borderColor: GB_ClassPalette.borderAt(slot),
    );

    classes.value = [...classes.value, created];
    return created;
  }

  /// True when [name] is already taken, ignoring case and surrounding spaces —
  /// what the add form checks before letting a duplicate through.
  ///
  /// [ignoreId] excludes one class from the comparison, which is what the
  /// rename form needs: a class is allowed to keep its own name, so without
  /// this, saving the edit dialog unchanged would report a clash with itself.
  static bool nameExists(String name, {int? ignoreId}) {
    final String candidate = name.trim().toLowerCase();
    return classes.value.any(
      (GB_ClassInfo item) =>
          item.id != ignoreId && item.name.toLowerCase() == candidate,
    );
  }

  /// Renames a class and returns it in its new form, or null if [id] is gone.
  ///
  /// A replacement [GB_ClassInfo] rather than a mutated one: the model is
  /// immutable, and every colour and id is carried across so a rename cannot
  /// quietly reshuffle the class's tint on the dashboard.
  static GB_ClassInfo? renameClass(int id, String name) {
    final int index =
        classes.value.indexWhere((GB_ClassInfo item) => item.id == id);
    if (index == -1) return null;

    final GB_ClassInfo existing = classes.value[index];
    final GB_ClassInfo renamed = GB_ClassInfo(
      id: existing.id,
      name: name.trim(),
      subtitle: existing.subtitle,
      imagePath: existing.imagePath,
      fillColor: existing.fillColor,
      borderColor: existing.borderColor,
    );

    final List<GB_ClassInfo> updated = List<GB_ClassInfo>.from(classes.value);
    updated[index] = renamed;
    classes.value = updated;

    return renamed;
  }

  /// The class with [id], or null once it has been deleted.
  static GB_ClassInfo? byId(int id) {
    for (final GB_ClassInfo item in classes.value) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Puts the store back to a freshly-launched state.
  ///
  /// Static state outlives an individual test, so without this the seeded list,
  /// the id counter, and anything a previous test added would leak into the
  /// next one and make results depend on test order.
  @visibleForTesting
  static void resetForTest() {
    _nextId = _seed.length;
    classes.value = List<GB_ClassInfo>.from(_seed);
  }

  static void removeClass(int id) {
    classes.value = classes.value
        .where((GB_ClassInfo item) => item.id != id)
        .toList();
  }
}
