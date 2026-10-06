part of 'project_workbench_sidebar.dart';

class const _WorkspaceRow({
  required final Project project,
  required final Workspace workspace,

  /// Registered SSH target for a remote workspace, or null when the workspace
  /// is local or its host was removed from Settings.
  final SshTarget? hostTarget,
  required final List<WorkspaceAgentRun> agentRuns,
  required final List<WorkspaceAgentRunGroup> agentRunGroups,

  /// Most urgent run across every agent in the workspace, main and secondary
  /// alike. Drives the trailing badge.
  required final AgentStatusEntry? workspaceStatus,

  /// The single main-panel agent merged onto this row, if any. Drives the
  /// leading glyph and the agent icon.
  final AgentStatusEntry? primaryStatus,
  required final bool hasTerminalTabs,
  required final bool isActive,
  required final String? activeTabId,
  required final bool showProject,
  required final bool expanded,
  required final bool isPinnedCopy,
  required final VoidCallback onTap,
  required final VoidCallback onOpenFolder,
  required final VoidCallback onCopyPath,
  required final VoidCallback onOpenInBrowser,
  required final VoidCallback onOpenProjectSettings,
  required final VoidCallback onSleep,
  final VoidCallback? onToggleArchived,
  required final VoidCallback onToggleExpanded,
  required final String fileManagerLabel,
  required final VoidCallback onRename,
  required final VoidCallback onSetPinned,
  final VoidCallback? onPinWorkspaceTree,
  final VoidCallback? onUnpinWorkspaceTree,
  required final VoidCallback onManageTags,
  required final VoidCallback onSetParent,
  required final _TerminalTabCallback onSelectTerminal,
  required final _TerminalTabCallback onCloseTerminal,
  final int visibleChildCount = 0,
  final bool childrenCollapsed = false,
  final VoidCallback? onToggleChildren,
  final List<WorkspaceSection> sections = const <WorkspaceSection>[],
  final bool hasTreeSection = false,
  final void Function(_SectionTarget target, bool create)? onSetSection,
  final void Function(_SectionTarget target)? onClearSection,
  final void Function(_SectionTarget target, String sectionId)? onAssignSection,
  final VoidCallback? onClearParent,
  final VoidCallback? onDelete,
  final VoidCallback? onHandOff,
  final VoidCallback? onHandOn,
}) extends StatefulWidget {
  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  /// Fixed leading slot so the status dot (8) and agent glyphs (~12–13) do not
  /// shift the workspace name when the indicator swaps.
  static const double _statusSlotSize = 14;

  /// Header widths below this hide the agent glyph and the inline metadata
  /// trays when a status badge needs the room; at the default sidebar width
  /// the name would otherwise truncate to a few characters.
  static const double _compactTrayWidth = AleraTokens.sidebarDefaultWidth;

  bool _hovered = false;

  String _buildBranchLabel() {
    final branch = widget.workspace.branch;
    if (branch != null && branch.isNotEmpty) {
      return branch;
    }
    if (widget.project.isFolder) {
      return 'Local Folder';
    }
    return 'Git Repository';
  }

  List<String> _tagLabels() {
    final source = widget.workspace.tagNames.isNotEmpty
        ? widget.workspace.tagNames
        : widget.workspace.tagIds;
    return source
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  String? _remoteHostId() {
    final hostId = widget.workspace.hostId.trim();
    if (hostId.isEmpty || hostId == 'local') {
      return null;
    }
    return hostId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final hasAgents = widget.agentRuns.isNotEmpty;

    final badge = agentRunStatusBadge(widget.workspaceStatus);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
          child: AleraActiveRail(
            active: isActive,
            child: AnimatedContainer(
              duration: AleraTokens.durationMid,
              decoration: BoxDecoration(
                color: isActive
                    ? AleraActiveRail.selectedColor
                    : (_hovered ? AleraTokens.surface : Colors.transparent),
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
              child: InkWell(
                key: ValueKey<String>(
                  'workspace-row:${widget.isPinnedCopy ? 'pinned' : 'regular'}:${widget.workspace.id}',
                ),
                onTap: widget.onTap,
                mouseCursor: SystemMouseCursors.click,
                // The animated surface above owns the hover fill.
                hoverColor: Colors.transparent,
                borderRadius: .circular(AleraTokens.radiusLg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                    vertical: AleraTokens.space6,
                  ),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    mainAxisSize: .min,
                    children: <Widget>[
                      LayoutBuilder(
                        builder: (context, constraints) => _buildHeader(
                          theme: theme,
                          // A status badge outranks the agent glyph and the
                          // inline metadata trays when the row is too narrow
                          // for all of them.
                          compact:
                              badge != null &&
                              constraints.maxWidth < _compactTrayWidth,
                          badgeMaxWidth: constraints.maxWidth / 2,
                          hasBadge: badge != null,
                        ),
                      ),
                      if (hasAgents && widget.expanded) ...<Widget>[
                        const SizedBox(height: AleraTokens.space4),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AleraTokens.space20,
                          ),
                          child: _WorkspaceAgentRunList(
                            workspace: widget.workspace,
                            runs: widget.agentRuns,
                            workspaceIsActive: widget.isActive,
                            activeTabId: widget.activeTabId,
                            onSelectTerminal: widget.onSelectTerminal,
                            onCloseTerminal: widget.onCloseTerminal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required ThemeData theme,
    required bool compact,
    required double badgeMaxWidth,
    required bool hasBadge,
  }) {
    final isActive = widget.isActive;
    final hasAgents = widget.agentRuns.isNotEmpty;
    return Row(
      crossAxisAlignment: .center,
      children: <Widget>[
        SizedBox.square(
          dimension: _statusSlotSize,
          child: Center(
            // One widget type in this slot regardless of state: swapping
            // types here destroyed the element and restarted the spinner
            // whenever an agent started or finished.
            child: AgentRunStateIndicator(
              key: const ValueKey<String>('workspace-status-glyph'),
              status: widget.primaryStatus,
              size: _statusSlotSize - 1,
              idleDotActive: isActive || widget.hasTerminalTabs,
            ),
          ),
        ),
        const SizedBox(width: AleraTokens.space8),
        if (widget.primaryStatus case final AgentStatusEntry primary
            when !compact) ...<Widget>[
          Tooltip(
            message: _agentRunDescription(primary),
            child: AgentIdentityIcon(
              agentType: primary.agentType,
              size: AleraTokens.space16,
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(width: AleraTokens.space6),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: .min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    widget.workspace.name,
                    key: const Key('workspace-row-name'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isActive || _hovered
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                if (!compact) ..._buildInlineTrays(theme),
              ],
            ),
          ),
        ),
        if (hasBadge) ...<Widget>[
          const SizedBox(width: AleraTokens.space6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: badgeMaxWidth),
            child: AgentRunStatusBadge(
              key: const Key('workspace-status-badge'),
              status: widget.workspaceStatus,
            ),
          ),
        ],
        if (hasAgents ||
            (widget.visibleChildCount > 0 &&
                widget.onToggleChildren != null)) ...<Widget>[
          const SizedBox(width: AleraTokens.space8),
          _WorkspaceIconTray(
            visibleChildCount: widget.visibleChildCount,
            childrenCollapsed: widget.childrenCollapsed,
            onToggleChildren: widget.onToggleChildren,
            agentGroups: widget.agentRunGroups,
            agentsExpanded: widget.expanded,
            onToggleAgents: hasAgents ? widget.onToggleExpanded : null,
            agentTooltip: hasAgents
                ? _agentTrayTooltip(
                    runs: widget.agentRuns,
                    expanded: widget.expanded,
                  )
                : null,
          ),
        ],
      ],
    );
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
        Tooltip(
          message: workspaceHostTooltip(
            hostId: hostId,
            target: widget.hostTarget,
          ),
          child: AleraHostOsIcon(
            key: const Key('workspace-tray-host'),
            os: sshTargetHostOs(widget.hostTarget),
            size: AleraTokens.iconSm,
          ),
        ),
      ],
    ];
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
    return _agentRunDescription(runs.single.status);
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
