import 'package:flutter/widgets.dart';

// Subset of the desktop `lib/src/design_system/icons/alera_codicons.dart`,
// duplicated because `alera_mobile` does not depend on the root package. Keep
// the code points and the bundled font version in sync.

/// VS Code Codicons used by the mobile companion.
///
/// Code points come from `@vscode/codicons` 0.0.46-24. The bundled font is
/// licensed under CC BY 4.0; see `assets/fonts/VSCodeCodicons-LICENSE.txt`.
abstract final class const AleraCodicons._() {
  static const String _family = 'Alera Codicons';

  static const IconData terminalLinux = IconData(0xebc6, fontFamily: _family);
}
