import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

class WorkbenchStatusBar extends StatelessWidget {
  const WorkbenchStatusBar({
    super.key,
    required this.workspace,
    required this.activeTab,
    required this.tabCount,
  });

  final Workspace? workspace;
  final TerminalTabRecord? activeTab;
  final int tabCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AleraTokens.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          if (workspace case final Workspace value) ...<Widget>[
            _StatusChip(
              label: value.isMain ? 'Main workspace' : 'Linked workspace',
              color: value.isMain ? AleraTokens.success : AleraTokens.accent,
            ),
            const SizedBox(width: AleraTokens.space8),
            _StatusChip(
              label: value.branch,
              color: AleraTokens.foregroundMuted,
            ),
            if (value.sourceBranch case final String sourceBranch) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              _StatusChip(
                label: 'from $sourceBranch',
                color: AleraTokens.foregroundFaint,
              ),
            ],
            const SizedBox(width: AleraTokens.space8),
            _StatusChip(
              label: '$tabCount tab${tabCount == 1 ? '' : 's'}',
              color: AleraTokens.foregroundMuted,
            ),
          ] else
            const _StatusChip(
              label: 'No workspace selected',
              color: AleraTokens.foregroundMuted,
            ),
          const Spacer(),
          if (activeTab != null) ...<Widget>[
            Text(
              activeTab!.title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(width: AleraTokens.space12),
          ],
          Flexible(
            child: Text(
              workspace?.path ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AleraTokens.monoStyle.copyWith(
                fontSize: 10,
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: AleraTokens.space4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
