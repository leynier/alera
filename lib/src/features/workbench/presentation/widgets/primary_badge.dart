import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small pill rendered next to a workspace name when the workspace points at
/// the project's main worktree.
class PrimaryBadge extends StatelessWidget {
  const PrimaryBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      ),
      child: Text(
        'primary',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}
