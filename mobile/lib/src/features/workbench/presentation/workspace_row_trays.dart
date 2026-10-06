part of 'workspace_row_widgets.dart';

class const _WorkspaceStatusIndicator({
  required final AgentPresenceSummary? primary,
  required final bool active,
}) extends StatelessWidget {
  static const double _glyphSize = 13;

  /// Spoken in place of the glyph, which only says its state through color
  /// and shape.
  String get _semanticLabel {
    final primary = this.primary;
    if (primary == null) {
      return active ? 'Terminal open' : 'Idle';
    }
    if (primary.interrupted == true) {
      return 'Agent interrupted';
    }
    return switch (primary.state) {
      'working' => 'Agent working',
      'waiting' => 'Agent waiting for input',
      'blocked' => 'Agent blocked',
      _ => 'Agent done',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      excludeSemantics: true,
      child: _glyph(),
    );
  }

  Widget _glyph() {
    if (primary case final AgentPresenceSummary status) {
      return AgentRunStateIndicator(
        key: const Key('workspace-status-glyph'),
        status: status,
        size: _glyphSize,
      );
    }
    return Container(
      width: AleraTokens.spaceSm,
      height: AleraTokens.spaceSm,
      decoration: BoxDecoration(
        color: active ? AleraTokens.success : AleraTokens.foregroundFaint,
        shape: .circle,
      ),
    );
  }
}

/// Trailing label summarizing every agent in the workspace: the most urgent
/// state that needs the user, or Done once nothing is still running. Working
/// and idle workspaces show no label.
class const _WorkspaceStatusBadge({
  required final String label,
  required final AleraBadgeTone tone,
}) extends StatelessWidget {
  static _WorkspaceStatusBadge? forStatus(AgentPresenceSummary? status) {
    if (status == null) {
      return null;
    }
    if (status.interrupted == true) {
      return const _WorkspaceStatusBadge(
        label: 'Interrupted',
        tone: AleraBadgeTone.error,
      );
    }
    return switch (status.state) {
      'waiting' => const _WorkspaceStatusBadge(
        label: 'Needs Input',
        tone: AleraBadgeTone.attention,
      ),
      'blocked' => const _WorkspaceStatusBadge(
        label: 'Blocked',
        tone: AleraBadgeTone.error,
      ),
      'done' => const _WorkspaceStatusBadge(
        label: 'Done',
        tone: AleraBadgeTone.success,
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Spoken on its own: the leading glyph only describes the main agent,
    // while the badge can come from a secondary one.
    return AleraBadge(
      key: const Key('workspace-status-badge'),
      label: label,
      tone: tone,
    );
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
                        size: AleraTokens.rowMetaIcon,
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
                        size: AleraTokens.rowMetaIcon,
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
    final title = mobileAgentRunTitle(status);
    final activity = mobileAgentRunActivity(status);
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
              AgentRunStateIndicator(
                status: status,
                size: AleraTokens.rowMetaIcon,
              ),
              const SizedBox(width: AleraTokens.space6),
              AgentIdentityIcon(
                agentType: status.agentType,
                size: AleraTokens.rowMetaIcon,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
                      ),
                    ),
                    if (activity != null)
                      Text(
                        activity,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                          fontWeight: .w500,
                        ),
                      ),
                  ],
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
