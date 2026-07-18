import 'dart:io';

import 'package:image/image.dart' as img;

/// Composes the Windows/Linux launcher icon: a white rounded square with the
/// black Alera logo centered on top. Regenerate with
/// `dart run tool/branding/generate_desktop_icon.dart`, then run
/// `dart run flutter_launcher_icons` to refresh the Windows .ico.
void main() {
  const size = 1024;
  const cornerRadius = size * 0.22;
  const logoFraction = 0.70;
  const sourcePath = 'assets/logo/alera-logo.png';
  const outputPath = 'assets/logo/alera-logo-desktop.png';

  final source = img.decodePng(File(sourcePath).readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode $sourcePath');
    exitCode = 1;
    return;
  }

  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fillRect(
    canvas,
    x1: 0,
    y1: 0,
    x2: size - 1,
    y2: size - 1,
    radius: cornerRadius,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  final logoSize = (size * logoFraction).round();
  final logo = img.copyResize(
    source,
    width: logoSize,
    height: logoSize,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    logo,
    dstX: (size - logoSize) ~/ 2,
    dstY: (size - logoSize) ~/ 2,
  );

  File(outputPath).writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Wrote $outputPath (${size}x$size)');
}
