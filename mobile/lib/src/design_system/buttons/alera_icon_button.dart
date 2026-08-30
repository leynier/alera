import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Compact icon button used across toolbars and secondary actions. Defaults to
/// [AleraTokens.minTapTarget] for comfortable finger tap targets.
class const AleraIconButton({
  super.key,
  final String? tooltip,
  required final VoidCallback? onPressed,
  required final IconData icon,
  final double iconSize = 16,
  final double minSize = AleraTokens.minTapTarget,
  final Color iconColor = AleraTokens.foregroundMuted,
  final Color? backgroundColor,
  final Color? hoverColor,
  final Color? borderColor,
  final double borderRadius = AleraTokens.radiusMd,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
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
