import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:flutter/material.dart';

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
    required this.terminalTabCount,
    required this.agentsExpanded,
    required this.onToggleAgents,
    required this.onAgentTap,
    required this.onCloseAgent,
    this.agentPresence = const <AgentPresenceSummary>[],
  });

  final MobileWorkspaceEntryRow row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onToggleChildren;
  final int terminalTabCount;
  final bool agentsExpanded;
  final VoidCallback onToggleAgents;
  final ValueChanged<AgentPresenceSummary> onAgentTap;
  final ValueChanged<AgentPresenceSummary> onCloseAgent;
  final List<AgentPresenceSummary> agentPresence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    final workspace = entry.workspace;
    final subtitle = workspace.branch ?? workspace.path;
    final statusColor = _workspaceStatusColor(context);
    final left =
        AleraTokens.spaceLg +
        (row.isPinnedCopy ? 0 : entry.depth) * AleraTokens.spaceLg;
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: EdgeInsets.only(
              left: left,
              right: AleraTokens.spaceSm,
              top: AleraTokens.spaceSm,
              bottom: AleraTokens.spaceSm,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: AleraTokens.spaceSm,
                  height: AleraTokens.spaceSm,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AleraTokens.spaceSm),
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
                          if (workspace.isPinned &&
                              !row.isPinnedCopy) ...<Widget>[
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
                _WorkspaceMetadataTray(
                  isDefault: workspace.isMain,
                  childCount: entry.visibleChildCount,
                  statuses: agentPresence,
                  agentsExpanded: agentsExpanded,
                  onToggleAgents: onToggleAgents,
                ),
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
        ),
        if (agentsExpanded)
          for (final status in agentPresence)
            _AgentPresenceRow(
              status: status,
              left: left + AleraTokens.spaceXl + AleraTokens.spaceLg,
              onTap: () => onAgentTap(status),
              onClose: () => onCloseAgent(status),
            ),
      ],
    );
  }

  Color _workspaceStatusColor(BuildContext context) {
    if (agentPresence.isNotEmpty) {
      return _stateColor(context, _mostUrgentState(agentPresence));
    }
    if (terminalTabCount > 0) {
      return AleraTokens.success;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class _WorkspaceMetadataTray extends StatelessWidget {
  const _WorkspaceMetadataTray({
    required this.isDefault,
    required this.childCount,
    required this.statuses,
    required this.agentsExpanded,
    required this.onToggleAgents,
  });

  final bool isDefault;
  final int childCount;
  final List<AgentPresenceSummary> statuses;
  final bool agentsExpanded;
  final VoidCallback onToggleAgents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isDefault)
          Tooltip(
            message: 'Default Workspace',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.home_outlined,
                  size: AleraTokens.spaceLg,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AleraTokens.spaceXs),
                Text('Default', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        if (childCount > 0) ...<Widget>[
          const SizedBox(width: AleraTokens.spaceSm),
          Tooltip(
            message: '$childCount Child Workspaces',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.account_tree_outlined,
                  size: AleraTokens.spaceLg,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Text(childCount.toString(), style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
        if (statuses.isNotEmpty) ...<Widget>[
          const SizedBox(width: AleraTokens.spaceSm),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: agentsExpanded ? 'Collapse Agents' : 'Expand Agents',
            onPressed: onToggleAgents,
            icon: Badge(
              label: Text(statuses.length.toString()),
              backgroundColor: _stateColor(context, _mostUrgentState(statuses)),
              child: Icon(
                agentsExpanded ? Icons.expand_less : Icons.smart_toy_outlined,
                color: _stateColor(context, _mostUrgentState(statuses)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AgentPresenceRow extends StatelessWidget {
  const _AgentPresenceRow({
    required this.status,
    required this.left,
    required this.onTap,
    required this.onClose,
  });

  final AgentPresenceSummary status;
  final double left;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _stateColor(context, status.state);
    final detail =
        status.toolName ??
        (status.prompt.isNotEmpty
            ? status.prompt
            : status.lastAssistantMessage);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          left,
          AleraTokens.spaceXs,
          AleraTokens.spaceSm,
          AleraTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.smart_toy_outlined,
              size: AleraTokens.spaceLg,
              color: color,
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${_agentLabel(status.agentType)} - ${_stateLabel(status.state)}',
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                  if (detail != null && detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close Agent Terminal',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

Color _stateColor(BuildContext context, String state) => switch (state) {
  'blocked' => Theme.of(context).colorScheme.error,
  'waiting' => AleraTokens.warning,
  'working' => AleraTokens.info,
  _ => AleraTokens.success,
};

String _agentLabel(String agentType) => switch (agentType) {
  'codex' => 'Codex',
  'claude' => 'Claude',
  'copilot' => 'Copilot',
  'cursor' => 'Cursor',
  'agy' => 'Agy',
  'opencode' => 'OpenCode',
  'pi' => 'Pi',
  'amp' => 'Amp',
  'grok' => 'Grok',
  _ => 'Agent',
};

String _stateLabel(String state) => switch (state) {
  'working' => 'Working',
  'waiting' => 'Waiting',
  'blocked' => 'Blocked',
  _ => 'Done',
};

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
