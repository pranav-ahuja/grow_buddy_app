/// Turns the Grow Buddy logo into the square source images the launcher icon
/// generator needs.
///
/// The logo at assets/images/splash_image.png is 846x633 with a transparent
/// background. A launcher icon has to be square and, on iOS, opaque — handing
/// the landscape art straight to flutter_launcher_icons makes it stretch the
/// logo to fill a square, which distorts it. So the art is scaled to fit and
/// centred on a square canvas here first.
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

import 'package:image/image.dart';

/// Launcher icons are authored at 1024 and downscaled by the generator.
const int kCanvas = 1024;

const String kSource = "assets/images/splash_image.png";
const String kLegacyOut = "tool/icon/app_icon.png";
const String kForegroundOut = "tool/icon/app_icon_foreground.png";

/// Share of the canvas width the logo spans.
///
/// The adaptive foreground is the smaller of the two: a launcher may mask the
/// icon to a circle, which cuts the corners off the square, so anything outside
/// the middle ~66% is not guaranteed to survive.
const double kLegacyScale = 0.86;
const double kForegroundScale = 0.62;

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

  final Image? logo = decodePng(source.readAsBytesSync());
  if (logo == null) {
    stderr.writeln("$kSource is not a readable PNG");
    exitCode = 1;
    return;
  }

  _write(kLegacyOut, logo, scale: kLegacyScale, background: kBackground);
  _write(kForegroundOut, logo, scale: kForegroundScale, background: null);
}

/// Centres [logo] on a [kCanvas]-square canvas at [scale] of its width.
void _write(
  String path,
  Image logo, {
  required double scale,
  required Color? background,
}) {
  // Fitted by width: the logo is wider than it is tall, so width is what runs
  // out of canvas first.
  final int width = (kCanvas * scale).round();
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
