import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small bordered square that previews a single color. Used next to color
/// inputs (e.g. terminal palette overrides).
class AleraColorSwatch extends StatelessWidget {
  const AleraColorSwatch({super.key, required this.color, this.size = 30});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
    );
  }
}
