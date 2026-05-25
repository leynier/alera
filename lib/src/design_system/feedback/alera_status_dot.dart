import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small circular indicator. Green when [active]; muted gray otherwise. Used at
/// the left of workspace/terminal rows to signal the currently active one.
class AleraStatusDot extends StatelessWidget {
  const AleraStatusDot({super.key, required this.active, this.size = 8});

  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? AleraTokens.success : AleraTokens.foregroundFaint,
        shape: BoxShape.circle,
      ),
    );
  }
}
