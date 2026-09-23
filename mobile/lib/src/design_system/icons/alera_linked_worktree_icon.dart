import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

// Duplicated from the desktop
// `lib/src/design_system/icons/alera_linked_worktree_icon.dart` because
// `alera_mobile` does not depend on the root package. Keep both in sync.

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
