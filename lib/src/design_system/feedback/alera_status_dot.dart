import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small circular indicator. Green when [active]; muted gray otherwise. Used at
/// the left of workspace/terminal rows to signal the currently active one.
class const AleraStatusDot({
  super.key,
  required final bool active,
  final double size = 8,
  final Color? color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            color ??
            (active ? AleraTokens.success : AleraTokens.foregroundFaint),
        shape: .circle,
      ),
    );
  }
}
