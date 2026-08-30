import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Compact icon button used across the sidebar header, search bar and
/// secondary toolbars. Honors the design system tokens (radius, foreground,
/// hit area) so callers don't sprinkle layout literals at each call site.
class const AleraIconButton({
  super.key,
  final String? tooltip,
  required final VoidCallback? onPressed,
  required final IconData icon,
  final double iconSize = defaultIconSize,
  final double minSize = defaultMinSize,
  final Color iconColor = AleraTokens.foregroundMuted,
  final Color? backgroundColor,
  final Color? hoverColor,
  final Color? borderColor,
  final double borderRadius = AleraTokens.radiusMd,
}) extends StatelessWidget {
  static const double defaultIconSize = 16;
  static const double defaultMinSize = 30;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      mouseCursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      icon: Icon(icon, size: iconSize, color: iconColor),
      visualDensity: .compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        hoverColor: hoverColor,
        minimumSize: Size(minSize, minSize),
        maximumSize: Size(minSize, minSize),
        tapTargetSize: .shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!),
        ),
      ),
    );
  }
}
