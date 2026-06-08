import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vscode_material_icon_theme/vscode_material_icon_theme.dart';

enum AleraFileIconKind { file, folder, symlink, generic }

class AleraFileIcon extends StatelessWidget {
  const AleraFileIcon({
    super.key,
    required this.pathOrName,
    required this.kind,
    this.isExpanded = false,
    this.size = 16,
    this.fallbackColor = AleraTokens.foregroundMuted,
  });

  final String pathOrName;
  final AleraFileIconKind kind;
  final bool isExpanded;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: switch (kind) {
        AleraFileIconKind.file => _svgIcon(
          fileToIcon(_iconName(pathOrName)),
          fallback: AleraIcons.file,
        ),
        AleraFileIconKind.folder => _svgIcon(
          directoryToIcon(_iconName(pathOrName), isExpanded: isExpanded),
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
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      placeholderBuilder: (_) =>
          Icon(fallback, size: size, color: fallbackColor),
      errorBuilder: (_, _, _) =>
          Icon(fallback, size: size, color: fallbackColor),
    );
  }

  String _iconName(String pathOrName) {
    final lastSlash = pathOrName.lastIndexOf('/');
    final lastBackslash = pathOrName.lastIndexOf(r'\');
    final index = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    final basename = index < 0 ? pathOrName : pathOrName.substring(index + 1);
    return basename.toLowerCase();
  }
}
