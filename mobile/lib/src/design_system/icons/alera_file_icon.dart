import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vscode_material_icon_theme/vscode_material_icon_theme.dart';

// Duplicated from the desktop `lib/src/design_system/icons/alera_file_icon.dart`
// because `alera_mobile` does not depend on the root package. Keep both in sync
// so the phone and the desktop draw the same glyph for a given path.

enum AleraFileIconKind {
  file,
  folder,
  symlink,
  generic;

  /// Maps a workspace entry `kind` reported by the runtime host.
  static AleraFileIconKind fromEntryKind(String kind) => switch (kind) {
    'directory' => folder,
    'file' => file,
    'symlink' => symlink,
    _ => generic,
  };
}

class const AleraFileIcon({
  super.key,
  required final String pathOrName,
  required final AleraFileIconKind kind,
  final bool isExpanded = false,
  final double size = AleraTokens.iconMd,
  final Color fallbackColor = AleraTokens.foregroundMuted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: switch (kind) {
        AleraFileIconKind.file => _svgIcon(
          fileToIcon(aleraFileIconName(pathOrName)),
          fallback: AleraIcons.file,
        ),
        AleraFileIconKind.folder => _svgIcon(
          directoryToIcon(
            aleraFileIconName(pathOrName),
            isExpanded: isExpanded,
          ),
          fallback: isExpanded ? AleraIcons.folderOpen : AleraIcons.folder,
        ),
        AleraFileIconKind.symlink => Icon(
          AleraIcons.link,
          size: size,
          color: fallbackColor,
        ),
        AleraFileIconKind.generic => Icon(
          AleraIcons.fileGeneric,
          size: size,
          color: fallbackColor,
        ),
      },
    );
  }

  Widget _svgIcon(BytesLoader loader, {required IconData fallback}) {
    return SvgPicture(
      loader,
      width: size,
      height: size,
      fit: .contain,
      excludeFromSemantics: true,
      placeholderBuilder: (_) =>
          Icon(fallback, size: size, color: fallbackColor),
      errorBuilder: (_, _, _) =>
          Icon(fallback, size: size, color: fallbackColor),
    );
  }
}

/// Lowercase basename the icon theme matches against, for `/` and `\` paths.
@visibleForTesting
String aleraFileIconName(String pathOrName) {
  final lastSlash = pathOrName.lastIndexOf('/');
  final lastBackslash = pathOrName.lastIndexOf(r'\');
  final index = lastSlash > lastBackslash ? lastSlash : lastBackslash;
  final basename = index < 0 ? pathOrName : pathOrName.substring(index + 1);
  return basename.toLowerCase();
}
