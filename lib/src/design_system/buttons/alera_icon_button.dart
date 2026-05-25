import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Compact icon button used across the sidebar header, search bar and
/// secondary toolbars. Honors the design system tokens (radius, foreground,
/// hit area) so callers don't sprinkle layout literals at each call site.
class AleraIconButton extends StatelessWidget {
  const AleraIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.iconSize = 16,
    this.minSize = 30,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final double iconSize;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: AleraTokens.foregroundMuted),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
      style: IconButton.styleFrom(
        minimumSize: Size(minSize, minSize),
        maximumSize: Size(minSize, minSize),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
      ),
    );
  }
}
