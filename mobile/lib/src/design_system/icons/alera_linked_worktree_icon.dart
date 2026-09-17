import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

// Duplicated from the desktop
// `lib/src/design_system/icons/alera_linked_worktree_icon.dart` because
// `alera_mobile` does not depend on the root package. Keep both in sync.

/// Linked (secondary) worktree marker: [AleraIcons.gitBranch] on its side so
/// it stays a branch glyph without matching the upright branch icon used for
/// the workspace's current git branch on the same row.
class const AleraLinkedWorktreeIcon({
  super.key,
  this.size = AleraTokens.iconSm,
  this.color = AleraTokens.foregroundMuted,
}) extends StatelessWidget {
  /// Clockwise quarter turns applied to [AleraIcons.gitBranch].
  static const int quarterTurns = 3;

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Icon(AleraIcons.gitBranch, size: size, color: color),
    );
  }
}
