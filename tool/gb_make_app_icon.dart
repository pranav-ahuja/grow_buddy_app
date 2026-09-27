/// Turns the Grow Buddy logo into the square source images the launcher icon
/// generator needs.
///
/// The logo at assets/images/splash_image.png is 846x633 with a transparent
/// background. A launcher icon has to be square and, on iOS, opaque — handing
/// the landscape art straight to flutter_launcher_icons makes it stretch the
/// logo to fill a square, which distorts it. So the art is scaled to fit and
/// centred on a square canvas here first.
///
/// The source art also carries a wide transparent margin — the drawn logo is
/// only 631x509 of its 846x633 canvas. That margin is trimmed before scaling,
/// so the constants below describe the logo itself rather than the logo plus
/// whatever padding the export happened to include. Without the trim, a
/// nominal 0.62 scale put the logo at 46% of the canvas and the launcher icon
/// looked far too small.
///
/// Two outputs, because Android draws the icon two ways:
///   app_icon.png            — opaque, for the legacy icon and iOS, where the
///                             whole square is shown.
///   app_icon_foreground.png — transparent, and inset further, for the Android
///                             adaptive icon whose outer edge is masked away by
///                             the launcher's own shape.
///
/// The outputs live under tool/ rather than assets/: they are build inputs for
/// the icon generator, and pubspec bundles all of assets/images, so putting
/// them there would ship two megabyte-scale PNGs inside the app for nothing.
///
/// Run: dart run tool/gb_make_app_icon.dart
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart';

/// Launcher icons are authored at 1024 and downscaled by the generator.
const int kCanvas = 1024;

const String kSource = "assets/images/splash_image.png";
const String kLegacyOut = "tool/icon/app_icon.png";
const String kForegroundOut = "tool/icon/app_icon_foreground.png";

/// Share of the canvas width the trimmed logo spans on the opaque icon.
///
/// iOS and the legacy Android icon show the whole square, so this only needs to
/// leave a little breathing room around the art.
const double kLegacyScale = 0.80;

/// Share of the canvas the trimmed logo's *diagonal* spans on the adaptive
/// foreground.
///
/// Diagonal rather than width because a launcher may mask the icon to a circle:
/// what has to fit is the logo's bounding box inside that circle, and for
/// landscape art the corners are what run out of room first. Android's adaptive
/// icon shows the middle 72 of 108dp, so 0.66 sits just inside the largest
/// circle any launcher will draw.
const double kForegroundDiagonal = 0.66;

/// The app's background (kPrimaryColor2). The logo was drawn on white, so
/// anything else would put a ring around its anti-aliased edges.
final Color kBackground = ColorRgba8(255, 255, 255, 255);

void main() {
  final File source = File(kSource);
  if (!source.existsSync()) {
    stderr.writeln("Missing $kSource");
    exitCode = 1;
    return;
  }

  final Image? decoded = decodePng(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln("$kSource is not a readable PNG");
    exitCode = 1;
    return;
  }

  final Image logo = _trimTransparent(decoded);
  stdout.writeln(
    "Source ${decoded.width}x${decoded.height}, "
    "trimmed to ${logo.width}x${logo.height}",
  );

  // Fitted by width: the logo is wider than it is tall, so width is what runs
  // out of canvas first.
  _write(
    kLegacyOut,
    logo,
    width: (kCanvas * kLegacyScale).round(),
    background: kBackground,
  );

  // Fitted by diagonal, so the whole bounding box clears a circular mask.
  final double diagonal =
      math.sqrt(logo.width * logo.width + logo.height * logo.height);
  _write(
    kForegroundOut,
    logo,
    width: (logo.width * kCanvas * kForegroundDiagonal / diagonal).round(),
    background: null,
  );
}

/// Crops the fully transparent margin off [image].
///
/// Alpha above 8 rather than 0: the exported art has a faint anti-aliased halo
/// that would otherwise count as content and defeat the trim.
Image _trimTransparent(Image image) {
  int minX = image.width, minY = image.height, maxX = -1, maxY = -1;
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Fully transparent, or already tight: hand back what we were given.
  if (maxX < minX || maxY < minY) return image;

  return copyCrop(
    image,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
}

/// Centres [logo] on a [kCanvas]-square canvas at [width] pixels across.
void _write(
  String path,
  Image logo, {
  required int width,
  required Color? background,
}) {
  final int height = (width * logo.height / logo.width).round();

  final Image scaled = copyResize(
    logo,
    width: width,
    height: height,
    interpolation: Interpolation.cubic,
  );

  // numChannels: 4 so the canvas starts fully transparent; the adaptive
  // foreground relies on that, and the opaque one paints over it.
  final Image canvas = Image(width: kCanvas, height: kCanvas, numChannels: 4);
  if (background != null) fill(canvas, color: background);

  compositeImage(
    canvas,
    scaled,
    dstX: (kCanvas - width) ~/ 2,
    dstY: (kCanvas - height) ~/ 2,
  );

  File(path).writeAsBytesSync(encodePng(canvas));
  stdout.writeln("Wrote $path (${kCanvas}x$kCanvas, logo ${width}x$height)");
}
