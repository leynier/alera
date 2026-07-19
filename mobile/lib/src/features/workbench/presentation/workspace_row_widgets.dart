import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:flutter/material.dart';

const double _treeIndentStep = 16;

class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    super.key,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.icon,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.spaceLg,
          vertical: AleraTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: AleraTokens.spaceLg,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: AleraTokens.spaceLg,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AleraTokens.spaceSm),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              count.toString(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileWorkspaceListRow extends StatelessWidget {
  const MobileWorkspaceListRow({
    super.key,
    required this.row,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.onToggleChildren,
    this.agentPresence = const <AgentPresenceSummary>[],
  });

  final MobileWorkspaceEntryRow row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onToggleChildren;
  final List<AgentPresenceSummary> agentPresence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    final workspace = entry.workspace;
    final subtitle = workspace.branch ?? workspace.path;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(
          left:
              AleraTokens.spaceLg +
              (row.isPinnedCopy ? 0 : entry.depth) * _treeIndentStep,
          right: AleraTokens.spaceSm,
          top: AleraTokens.spaceSm,
          bottom: AleraTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              workspace.isMain
                  ? Icons.home_outlined
                  : Icons.account_tree_outlined,
              size: AleraTokens.spaceXl,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AleraTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          workspace.name,
                          style: theme.textTheme.bodyLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (workspace.isPinned && !row.isPinnedCopy) ...<Widget>[
                        const SizedBox(width: AleraTokens.spaceSm),
                        Icon(
                          Icons.push_pin,
                          size: AleraTokens.spaceMd,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AleraTokens.spaceXs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: workspace.branch != null
                          ? AleraTokens.monoFontFamily
                          : null,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (agentPresence.isNotEmpty)
              _AgentPresenceBadge(statuses: agentPresence),
            if (!row.isPinnedCopy && entry.hasVisibleChildren)
              IconButton(
                tooltip: entry.childrenCollapsed
                    ? 'Expand Children'
                    : 'Collapse Children',
                onPressed: onToggleChildren,
                icon: entry.childrenCollapsed
                    ? Badge.count(
                        count: entry.visibleChildCount,
                        child: const Icon(Icons.chevron_right),
                      )
                    : const Icon(Icons.expand_more),
              ),
            IconButton(
              tooltip: 'Workspace Actions',
              onPressed: onMore,
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentPresenceBadge extends StatelessWidget {
  const _AgentPresenceBadge({required this.statuses});

  final List<AgentPresenceSummary> statuses;

  @override
  Widget build(BuildContext context) {
    final state = _mostUrgentState(statuses);
    final color = switch (state) {
      'blocked' => Theme.of(context).colorScheme.error,
      'waiting' => AleraTokens.warning,
      'working' => AleraTokens.info,
      _ => AleraTokens.success,
    };
    return Badge(
      label: Text(statuses.length.toString()),
      backgroundColor: color,
      child: Icon(Icons.smart_toy_outlined, color: color),
    );
  }
}

String _mostUrgentState(List<AgentPresenceSummary> statuses) {
  const priority = <String, int>{
    'blocked': 4,
    'waiting': 3,
    'working': 2,
    'done': 1,
  };
  return statuses
      .map((status) => status.state)
      .reduce(
        (left, right) =>
            (priority[left] ?? 0) >= (priority[right] ?? 0) ? left : right,
      );
}
