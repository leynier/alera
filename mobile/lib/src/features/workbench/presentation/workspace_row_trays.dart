part of 'workspace_row_widgets.dart';

class const _WorkspaceStatusIndicator({
  required final bool hasAgents,
  required final String? state,
  required final bool? interrupted,
  required final bool active,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!hasAgents || state == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: active ? AleraTokens.success : AleraTokens.foregroundFaint,
          shape: .circle,
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

class const _WorkspaceActionTray({
  required final int childCount,
  required final bool childrenCollapsed,
  required final VoidCallback? onToggleChildren,
  required final List<AgentPresenceSummary> statuses,
  required final bool agentsExpanded,
  required final VoidCallback? onToggleAgents,
}) extends StatelessWidget {
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
            borderRadius: .circular(AleraTokens.radiusSm),
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
                    mainAxisSize: .min,
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
                          fontWeight: .w600,
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
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final (index, item) in items.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: AleraTokens.space6),
          item,
        ],
      ],
    );
  }
}

class const _AgentPresenceRow({
  required final AgentPresenceSummary status,
  required final VoidCallback onTap,
  required final VoidCallback onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _agentRunDescription(status);
    return InkWell(
      onTap: onTap,
      borderRadius: .circular(AleraTokens.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space6,
            vertical: AleraTokens.space8,
          ),
          child: Row(
            crossAxisAlignment: .center,
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
                  overflow: .ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                    fontWeight: .w500,
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
