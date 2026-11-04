part of 'project_workbench_sidebar.dart';

extension _WorkspaceRowInlineTrays on _WorkspaceRowState {
  String? _remoteHostId() {
    final hostId = widget.workspace.hostId.trim();
    if (hostId.isEmpty || hostId == 'local') {
      return null;
    }
    return hostId;
  }

  /// Metadata glyphs after the workspace name: project, role, pin, archive,
  /// branch, pull request, watch, linked issue, tags and remote host.
  List<Widget> _buildInlineTrays(ThemeData theme) {
    final branchLabel = _buildBranchLabel();
    final tags = _tagLabels();
    final hostId = _remoteHostId();
    final showProject = widget.showProject;
    return <Widget>[
      if (showProject) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: widget.project.name,
          child: const Icon(
            AleraIcons.folderSpecial,
            size: 12,
            color: AleraTokens.foregroundMuted,
            key: Key('workspace-tray-project'),
          ),
        ),
      ],
      if (WorkspaceRoleBadge.hasRole(widget.workspace)) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: widget.workspace.isMain
              ? 'Project folder'
              : 'Linked worktree',
          child: widget.workspace.isMain
              ? const Icon(
                  AleraIcons.workspaceMain,
                  size: 12,
                  color: AleraTokens.foregroundMuted,
                  key: Key('workspace-tray-home'),
                )
              : const AleraLinkedWorktreeIcon(
                  key: Key('workspace-tray-worktree'),
                ),
        ),
      ],
      if (widget.workspace.isPinned) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Pinned workspace',
          child: Icon(
            AleraIcons.pin,
            size: 12,
            color: AleraTokens.foregroundMuted,
            key: Key('workspace-tray-pinned'),
          ),
        ),
      ],
      if (widget.workspace.isArchived) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Archived workspace',
          child: Icon(
            AleraIcons.archive,
            size: 12,
            color: AleraTokens.foregroundMuted,
            key: Key('workspace-tray-archived'),
          ),
        ),
      ],
      const SizedBox(width: AleraTokens.space6),
      Tooltip(
        message: branchLabel,
        child: const Icon(
          AleraIcons.gitBranch,
          size: 12,
          color: AleraTokens.foregroundMuted,
          key: Key('workspace-tray-branch'),
        ),
      ),
      Consumer(
        builder: (context, ref, child) {
          final summary = ref.watch(
            workspacePullRequestSummaryProvider(widget.workspace.id),
          );
          if (summary == null) {
            return const SizedBox.shrink();
          }
          return Row(
            mainAxisSize: .min,
            children: <Widget>[
              const SizedBox(width: AleraTokens.space6),
              WorkspacePullRequestStatusIndicator(
                key: const Key('workspace-tray-pull-request'),
                summary: summary,
              ),
            ],
          );
        },
      ),
      WorkspacePullRequestWatchIndicator(workspaceId: widget.workspace.id),
      WorkspaceLinkedIssueTrayIcon(workspaceId: widget.workspace.id),
      if (tags.isNotEmpty) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: tags.join(', '),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              const Icon(
                AleraIcons.tag,
                size: 12,
                color: AleraTokens.foregroundMuted,
                key: Key('workspace-tray-tags'),
              ),
              const SizedBox(width: AleraTokens.space2),
              Text(
                '${tags.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontWeight: .w600,
                ),
              ),
            ],
          ),
        ),
      ],
      if (hostId != null) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        _WorkspaceHostMarker(hostId: hostId, target: widget.hostTarget),
      ],
    ];
  }
}

/// The remote host glyph on a workspace row. It fades and names the state
/// when the host is offline, failing or installing, so a row whose host is
/// down reads differently before the user opens it.
class const _WorkspaceHostMarker({
  required final String hostId,
  required final SshTarget? target,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (tooltip, dimmed) = ref.watch(
      remoteHostsControllerProvider.select((state) {
        final status = state.hostById(hostId)?.status;
        return (
          workspaceHostMarkerTooltip(
            hostId: hostId,
            target: target,
            status: status,
          ),
          workspaceHostMarkerDimmed(status),
        );
      }),
    );
    return Tooltip(
      message: tooltip,
      child: AleraHostOsIcon(
        key: const Key('workspace-tray-host'),
        os: sshTargetHostOs(target),
        size: AleraTokens.iconSm,
        color: dimmed
            ? AleraTokens.foregroundFaint
            : AleraTokens.foregroundMuted,
      ),
    );
  }
}

String _agentTrayTooltip({
  required List<WorkspaceAgentRun> runs,
  required bool expanded,
}) {
  if (expanded) {
    return 'Hide Agent Runs';
  }
  if (runs.length == 1) {
    return _agentRunDescription(runs.single);
  }
  return 'Show Agent Runs';
}

/// Right-side icon tray for expandable controls: agents and children.
class const _WorkspaceIconTray({
  required final int visibleChildCount,
  required final bool childrenCollapsed,
  required final VoidCallback? onToggleChildren,
  required final List<WorkspaceAgentRunGroup> agentGroups,
  required final bool agentsExpanded,
  required final VoidCallback? onToggleAgents,
  required final String? agentTooltip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[];

    if (onToggleAgents != null && agentGroups.isNotEmpty) {
      items.add(
        WorkspaceAgentCompactSummary(
          key: const Key('workspace-tray-agents'),
          groups: agentGroups,
          expanded: agentsExpanded,
          onToggle: onToggleAgents!,
          tooltipOverride: agentTooltip,
        ),
      );
    }

    if (visibleChildCount > 0 && onToggleChildren != null) {
      items.add(
        _TrayIconItem(
          key: const Key('workspace-tray-children'),
          tooltip: childrenCollapsed
              ? 'Show Child Workspaces'
              : 'Hide Child Workspaces',
          onTap: onToggleChildren,
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
                '$visibleChildCount',
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
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        for (final (index, item) in items.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: AleraTokens.space6),
          item,
        ],
      ],
    );
  }
}

class const _TrayIconItem({
  super.key,
  required final String tooltip,
  required final Widget child,
  final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space4,
        vertical: AleraTokens.space2,
      ),
      child: child,
    );
    return Tooltip(
      message: tooltip,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: .circular(AleraTokens.radiusXs),
              child: content,
            ),
    );
  }
}
