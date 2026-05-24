import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small circular indicator shown at the left of a workspace row. Green when
/// the workspace is the currently active one; muted gray otherwise.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.active, this.size = 8});

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
