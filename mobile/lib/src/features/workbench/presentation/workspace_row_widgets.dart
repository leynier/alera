import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_agent_compact_summary.dart';
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
    final expanded = !collapsed;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space2,
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space8,
            ),
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            alignment: Alignment.center,
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 14, color: AleraTokens.foregroundMuted),
                  const SizedBox(width: AleraTokens.space6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  count.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  expanded ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dense single-line workspace row mirroring the desktop sidebar anatomy.
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
    this.showProjectIcon = false,
    this.projectName,
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
  final bool showProjectIcon;
  final String? projectName;

  /// Fixed leading slot so status glyphs do not shift the title (desktop: 14).
  static const double _statusSlotSize = 14;
  static const double _trayIconSize = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    final workspace = entry.workspace;
    final tags = _tagLabels(workspace);
    final depthPad =
        (row.isPinnedCopy ? 0 : entry.depth) * AleraTokens.space12;
    final rowLeft = AleraTokens.space12 + depthPad;
    final canToggleChildren = !row.isPinnedCopy && entry.hasVisibleChildren;
    final hasAgents = agentPresence.isNotEmpty;
    final metadataIcons = <Widget>[
      if (showProjectIcon &&
          (projectName?.trim().isNotEmpty ?? false)) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: projectName!,
          child: const Icon(
            AleraIcons.folderSpecial,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
      if (workspace.isMain) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Default Workspace',
          child: Icon(
            AleraIcons.workspaceMain,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
      if (workspace.isPinned && !row.isPinnedCopy) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Pinned Workspace',
          child: Icon(
            AleraIcons.pin,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
      if (tags.isNotEmpty) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: tags.join(', '),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                AleraIcons.tag,
                size: _trayIconSize,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space2),
              Text(
                '${tags.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onLongPress,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AleraTokens.minTapTarget,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          rowLeft,
                          AleraTokens.space8,
                          AleraTokens.space4,
                          AleraTokens.space8,
                        ),
                        child: Row(
                          children: <Widget>[
                            SizedBox.square(
                              dimension: _statusSlotSize,
                              child: Center(
                                child: _WorkspaceStatusIndicator(
                                  hasAgents: hasAgents,
                                  state: hasAgents
                                      ? _mostUrgentState(agentPresence)
                                      : null,
                                  interrupted: hasAgents
                                      ? agentPresence
                                            .firstWhere(
                                              (status) =>
                                                  status.state ==
                                                  _mostUrgentState(
                                                    agentPresence,
                                                  ),
                                              orElse: () => agentPresence.first,
                                            )
                                            .interrupted
                                      : null,
                                  active: terminalTabCount > 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: AleraTokens.space8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        workspace.name,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: AleraTokens.foreground,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    ...metadataIcons,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasAgents || canToggleChildren)
                  _WorkspaceActionTray(
                    childCount: entry.visibleChildCount,
                    childrenCollapsed: entry.childrenCollapsed,
                    onToggleChildren: canToggleChildren
                        ? onToggleChildren
                        : null,
                    statuses: agentPresence,
                    agentsExpanded: agentsExpanded,
                    onToggleAgents: hasAgents ? onToggleAgents : null,
                  ),
                Align(
                  alignment: Alignment.center,
                  child: AleraIconButton(
                    tooltip: 'Workspace Actions',
                    onPressed: onMore,
                    icon: AleraIcons.more,
                    iconSize: 16,
                  ),
                ),
              ],
            ),
          ),
          if (hasAgents && agentsExpanded) ...<Widget>[
            const SizedBox(height: AleraTokens.space4),
            Padding(
              padding: EdgeInsets.only(left: rowLeft + AleraTokens.space20),
              child: Column(
                children: <Widget>[
                  for (final status in agentPresence)
                    _AgentPresenceRow(
                      status: status,
                      onTap: () => onAgentTap(status),
                      onClose: () => onCloseAgent(status),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceStatusIndicator extends StatelessWidget {
  const _WorkspaceStatusIndicator({
    required this.hasAgents,
    required this.state,
    required this.interrupted,
    required this.active,
  });

  final bool hasAgents;
  final String? state;
  final bool? interrupted;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!hasAgents || state == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: active ? AleraTokens.success : AleraTokens.foregroundFaint,
          shape: BoxShape.circle,
        ),
      );
    }
    if (state == 'working') {
      return const SizedBox.square(
        dimension: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.7,
          color: AleraTokens.warning,
        ),
      );
    }
    final color = interrupted == true
        ? AleraTokens.error
        : _stateColor(state!);
    final icon = interrupted == true
        ? AleraIcons.cancel
        : switch (state) {
            'waiting' || 'blocked' => AleraIcons.notifications,
            'done' => AleraIcons.success,
            _ => AleraIcons.success,
          };
    return Icon(icon, size: 13, color: color);
  }
}

class _WorkspaceActionTray extends StatelessWidget {
  const _WorkspaceActionTray({
    required this.childCount,
    required this.childrenCollapsed,
    required this.onToggleChildren,
    required this.statuses,
    required this.agentsExpanded,
    required this.onToggleAgents,
  });

  final int childCount;
  final bool childrenCollapsed;
  final VoidCallback? onToggleChildren;
  final List<AgentPresenceSummary> statuses;
  final bool agentsExpanded;
  final VoidCallback? onToggleAgents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[];

    if (onToggleAgents != null && statuses.isNotEmpty) {
      items.add(
        MobileWorkspaceAgentCompactSummary(
          groups: groupWorkspaceAgentRuns(statuses),
          expanded: agentsExpanded,
          onToggle: onToggleAgents!,
          fillHeight: true,
        ),
      );
    }

    if (childCount > 0 && onToggleChildren != null) {
      items.add(
        Tooltip(
          message: childrenCollapsed
              ? 'Show Child Workspaces'
              : 'Hide Child Workspaces',
          child: InkWell(
            onTap: onToggleChildren,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AleraTokens.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        AleraIcons.workspaceChildren,
                        size: 12,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space2),
                      Text(
                        '$childCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space2),
                      Icon(
                        childrenCollapsed
                            ? AleraIcons.chevronRight
                            : AleraIcons.chevronDown,
                        size: 12,
                        color: AleraTokens.foregroundMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, item) in items.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: AleraTokens.space6),
          item,
        ],
      ],
    );
  }
}

class _AgentPresenceRow extends StatelessWidget {
  const _AgentPresenceRow({
    required this.status,
    required this.onTap,
    required this.onClose,
  });

  final AgentPresenceSummary status;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _agentRunDescription(status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space6,
            vertical: AleraTokens.space8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              AgentRunStateIndicator(status: status, size: 12),
              const SizedBox(width: AleraTokens.space6),
              AgentIdentityIcon(
                agentType: status.agentType,
                size: 13,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: AleraTokens.space4),
                child: AleraIconButton(
                  tooltip: 'Close Terminal',
                  onPressed: onClose,
                  icon: AleraIcons.close,
                  iconSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<String> _tagLabels(WorkspaceSummary workspace) {
  final names = workspace.tagNames
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
  if (names.isNotEmpty) {
    return names;
  }
  return workspace.tagIds
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

String _agentRunDescription(AgentPresenceSummary status) {
  if (status.state == 'working') {
    final toolName = status.toolName?.trim() ?? '';
    final toolInput = status.toolInput?.trim() ?? '';
    if (toolName.isNotEmpty && toolInput.isNotEmpty) {
      return '$toolName: $toolInput';
    }
    if (toolName.isNotEmpty) {
      return toolName;
    }
  }
  final assistantMessage = status.lastAssistantMessage?.trim() ?? '';
  if (assistantMessage.isNotEmpty) {
    return assistantMessage;
  }
  return '${agentDisplayName(status.agentType)} · ${agentRunStateLabel(status)}';
}

Color _stateColor(String state) => switch (state) {
  'blocked' => AleraTokens.error,
  'waiting' => AleraTokens.warning,
  'working' => AleraTokens.warning,
  _ => AleraTokens.success,
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
