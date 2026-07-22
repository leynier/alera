part of 'workspace_row_widgets.dart';

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
    final color = interrupted == true ? AleraTokens.error : _stateColor(state!);
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
