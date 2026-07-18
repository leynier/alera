import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;

/// Converts ICO bytes to PNG bytes using the largest embedded frame; the
/// Flutter engine cannot decode ICO natively. CPU-bound: run via `compute`.
Uint8List decodeWorkspaceIcoToPngBytes(Uint8List bytes) {
  final image = _decodeLargestIcoFrame(bytes) ?? image_lib.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('ICO image cannot be decoded');
  }
  return image_lib.encodePng(image);
}

image_lib.Image? _decodeLargestIcoFrame(Uint8List bytes) {
  final decoder = image_lib.IcoDecoder();
  final info = decoder.startDecode(bytes);
  if (info is! image_lib.IcoInfo || info.images.isEmpty) {
    return null;
  }

  var largestFrame = 0;
  var largestArea = 0;
  for (var index = 0; index < info.images.length; index += 1) {
    final image = info.images[index];
    final width = image.width == 0 ? 256 : image.width;
    final height = image.height == 0 ? 256 : image.height;
    final area = width * height;
    if (area > largestArea) {
      largestArea = area;
      largestFrame = index;
    }
  }
  return decoder.decodeFrame(largestFrame);
}
