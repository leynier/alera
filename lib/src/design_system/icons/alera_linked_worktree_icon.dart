import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Linked (secondary) worktree marker: [AleraIcons.split] rotated 90 degrees
/// clockwise so it does not collide with the upright current-branch
/// [AleraIcons.gitBranch] on the same row.
class const AleraLinkedWorktreeIcon({
  super.key,
  this.size = AleraTokens.iconSm,
  this.color = AleraTokens.foregroundMuted,
}) extends StatelessWidget {
  /// Clockwise quarter turns applied to [AleraIcons.split].
  static const int quarterTurns = 1;

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Icon(AleraIcons.split, size: size, color: color),
    );
  }
}
