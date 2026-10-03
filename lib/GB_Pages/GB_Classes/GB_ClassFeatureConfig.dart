import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';

/// Which features each class shows on its screen.
///
/// **This file is meant to be edited by hand.** It is the one place that says
/// what a class offers, so turning a feature on for a class is a line here
/// rather than a change spread across the screens.
///
/// Why a config at all: the six tiles in `GB_ClassFeature.all` were drawn for
/// every class alike, but a nursery does not set homework and a senior class
/// does not want a fee tile in the middle of its lessons. Real teachers will
/// tell us which ones they actually want, class by class, and that answer will
/// keep changing — so it lives somewhere a change costs one line.
///
/// **Nothing is deleted when it is switched off.** A feature switched off is
/// still in the catalogue and its screen still exists; it is simply not drawn.
/// That is what makes turning one back on cheap.
///
/// The trade-off of keeping this in Dart rather than on the server: changing a
/// class's features needs a rebuild, and [perClass] is keyed by the server's
/// own class ids (`CL_000003`), which you have to look up. When that becomes
/// the wrong shape — most likely when a principal should set this themselves —
/// move the enabled set onto the `classes` row and have [enabledIdsFor] read
/// `GB_ClassInfo` instead. Every caller goes through [featuresFor], so that
/// swap touches this file and nothing else.
class GB_ClassFeatureConfig {
  const GB_ClassFeatureConfig._();

  /// What a class shows unless [perClass] says otherwise — which today is
  /// every class, including every newly created one.
  ///
  /// Homework and Attendance only, as of 2026-10-03. The other four are built
  /// and switched off, waiting on a teacher to ask for them.
  static const Set<String> defaultEnabled = <String>{
    GB_ClassFeature.homeworkId,
    GB_ClassFeature.attendanceId,
  };

  /// Per-class overrides, by the server's class id.
  ///
  /// An entry **replaces** [defaultEnabled] rather than adding to it, so a
  /// class listed here states its whole set — otherwise reading this file
  /// would not tell you what a class actually shows.
  ///
  /// Example, once a teacher asks for the fee tile back on one class:
  ///
  /// ```dart
  /// static const Map<String, Set<String>> perClass = <String, Set<String>>{
  ///   "CL_000003": <String>{
  ///     GB_ClassFeature.homeworkId,
  ///     GB_ClassFeature.attendanceId,
  ///     "fee_payment",
  ///   },
  /// };
  /// ```
  static const Map<String, Set<String>> perClass = <String, Set<String>>{};

  /// The ids enabled for [classId].
  static Set<String> enabledIdsFor(String classId) {
    assert(_idsAreKnown());
    return perClass[classId] ?? defaultEnabled;
  }

  /// The features [classId] shows, in the catalogue's order so the row reads
  /// the same way on every class.
  static List<GB_ClassFeature> featuresFor(String classId) {
    final Set<String> enabled = enabledIdsFor(classId);
    return GB_ClassFeature.all
        .where((GB_ClassFeature feature) => enabled.contains(feature.id))
        .toList();
  }

  /// Whether one named feature is on for [classId] — for code that guards a
  /// route rather than draws a row.
  static bool isEnabled(String classId, String featureId) =>
      enabledIdsFor(classId).contains(featureId);

  /// Debug-only guard against a typo in an id.
  ///
  /// A misspelt id is not an error on its own — it just matches no feature, so
  /// the tile quietly never appears and the config still reads as if it should.
  /// That is the kind of thing nobody notices for weeks, so it fails loudly in
  /// debug instead. Always returns true, to sit inside an [assert].
  static bool _idsAreKnown() {
    final Set<String> known = GB_ClassFeature.allIds;
    final Set<String> used = <String>{
      ...defaultEnabled,
      for (final Set<String> ids in perClass.values) ...ids,
    };
    final Set<String> unknown = used.difference(known);
    assert(
      unknown.isEmpty,
      "GB_ClassFeatureConfig names features that do not exist: "
      "${unknown.join(", ")}. Known ids: ${known.join(", ")}.",
    );
    return true;
  }
}
