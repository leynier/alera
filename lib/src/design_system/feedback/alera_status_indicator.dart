import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Icon framed inside a soft color-tinted square. The caller maps domain state
/// to an [icon] and [color]; this component owns only the framing so the same
/// look is reused for any status (updates, sync, validation, etc.).
class AleraStatusIndicator extends StatelessWidget {
  const AleraStatusIndicator({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: color.withAlpha(115)),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
