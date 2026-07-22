import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small circular indicator. Green when [active]; muted gray otherwise.
class AleraStatusDot extends StatelessWidget {
  const AleraStatusDot({
    super.key,
    required this.active,
    this.size = 8,
    this.color,
  });

  final bool active;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            color ??
            (active ? AleraTokens.success : AleraTokens.foregroundFaint),
        shape: BoxShape.circle,
      ),
    );
  }
}
