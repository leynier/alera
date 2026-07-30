import 'package:flutter/widgets.dart';

/// VS Code Codicons used by Alera's source-control surfaces.
///
/// Code points come from `@vscode/codicons` 0.0.46-24. The bundled font is
/// licensed under CC BY 4.0; see `assets/fonts/VSCodeCodicons-LICENSE.txt`.
abstract final class AleraCodicons {
  const AleraCodicons._();

  static const String _family = 'Alera Codicons';

  static const IconData add = IconData(0xea60, fontFamily: _family);
  static const IconData sync = IconData(0xea77, fontFamily: _family);
  static const IconData check = IconData(0xeab2, fontFamily: _family);
  static const IconData cloudUpload = IconData(0xeac3, fontFamily: _family);
  static const IconData discard = IconData(0xeae2, fontFamily: _family);
  static const IconData refresh = IconData(0xeb37, fontFamily: _family);
  static const IconData remove = IconData(0xeb3b, fontFamily: _family);
  static const IconData repoPull = IconData(0xeb40, fontFamily: _family);
  static const IconData repoPush = IconData(0xeb41, fontFamily: _family);
  static const IconData gitStash = IconData(0xec26, fontFamily: _family);
  static const IconData gitStashPop = IconData(0xec28, fontFamily: _family);
  static const IconData gitFetch = IconData(0xecb2, fontFamily: _family);
}
