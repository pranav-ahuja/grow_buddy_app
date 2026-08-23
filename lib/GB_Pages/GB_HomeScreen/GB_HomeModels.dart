import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// One card in the events carousel.
///
/// [imagePath] is an asset path for now. When events come from the backend this
/// becomes a URL and the card swaps `Image.asset` for `Image.network`; nothing
/// else about the card changes.
class GB_Event {
  final String title;

  /// The line under the title — on the mockup, "Classes: Nursery & KG".
  final String subtitle;
  final String imagePath;

  const GB_Event({
    required this.title,
    required this.subtitle,
    required this.imagePath,
  });
}

/// One row in the "Your classes at a glance!" list.
///
/// [fillColor]/[borderColor] travel with the class rather than being picked by
/// list position, so a class keeps its colour even if the list is reordered or
/// filtered. [GB_ClassPalette] hands out the mockup's five tints in order.
class GB_ClassInfo {
  final String name;

  /// "no. of students" on the mockup — the real count once the backend has one.
  final String subtitle;
  final String imagePath;
  final Color fillColor;
  final Color borderColor;

  const GB_ClassInfo({
    required this.name,
    required this.subtitle,
    required this.imagePath,
    required this.fillColor,
    required this.borderColor,
  });
}

/// The five fill/border pairs from the mockup, in order.
///
/// Kept as a cycle so a sixth class does not crash or come out uncoloured — it
/// simply reuses the first tint.
class GB_ClassPalette {
  const GB_ClassPalette._();

  static const List<Color> _fills = [
    kClassTileYellowFill,
    kClassTilePinkFill,
    kClassTileBlueFill,
    kClassTileGreenFill,
    kClassTilePurpleFill,
  ];

  static const List<Color> _borders = [
    kClassTileYellowBorder,
    kClassTilePinkBorder,
    kClassTileBlueBorder,
    kClassTileGreenBorder,
    kClassTilePurpleBorder,
  ];

  static Color fillAt(int index) => _fills[index % _fills.length];

  static Color borderAt(int index) => _borders[index % _borders.length];
}
