part of 'project_workbench_sidebar.dart';

class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow({
    required this.project,
    required this.workspace,
    required this.agentRuns,
    required this.agentRunGroups,
    required this.status,
    required this.hasTerminalTabs,
    required this.isActive,
    required this.activeTabId,
    required this.showProject,
    required this.expanded,
    required this.onTap,
    required this.onOpenFolder,
    required this.onCopyPath,
    required this.onSleep,
    required this.onToggleExpanded,
    required this.fileManagerLabel,
    required this.onRename,
    required this.onManageTags,
    required this.onSetParent,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
    this.visibleChildCount = 0,
    this.childrenCollapsed = false,
    this.onToggleChildren,
    this.onClearParent,
    this.onDelete,
  });

  final Project project;
  final Workspace workspace;
  final List<WorkspaceAgentRun> agentRuns;
  final List<WorkspaceAgentRunGroup> agentRunGroups;
  final AgentStatusEntry? status;
  final bool hasTerminalTabs;
  final bool isActive;
  final String? activeTabId;

  final bool showProject;
  final bool expanded;
  final int visibleChildCount;
  final bool childrenCollapsed;
  final VoidCallback? onToggleChildren;
  final VoidCallback onTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyPath;
  final VoidCallback onSleep;
  final VoidCallback onToggleExpanded;
  final String fileManagerLabel;
  final VoidCallback onRename;
  final VoidCallback onManageTags;
  final VoidCallback onSetParent;
  final _TerminalTabCallback onSelectTerminal;
  final _TerminalTabCallback onCloseTerminal;
  final VoidCallback? onClearParent;
  final VoidCallback? onDelete;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  static const String _renameAction = 'rename';
  static const String _openFolderAction = 'open-folder';
  static const String _copyPathAction = 'copy-path';
  static const String _sleepAction = 'sleep';
  static const String _manageTagsAction = 'manage-tags';
  static const String _setParentAction = 'set-parent';
  static const String _clearParentAction = 'clear-parent';
  static const String _removeAction = 'remove';

  /// Fixed leading slot so the status dot (8) and agent glyphs (~12–13) do not
  /// shift the workspace name when the indicator swaps.
  static const double _statusSlotSize = 14;

  bool _hovered = false;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const AleraDropdownEntry<String>(
          value: _renameAction,
          leading: Icon(AleraIcons.edit, size: 16),
          label: 'Rename',
        ),
        const AleraDropdownEntry<String>(
          value: _manageTagsAction,
          leading: Icon(AleraIcons.tag, size: 16),
          label: 'Manage Tags',
        ),
        const AleraDropdownEntry<String>(
          value: _setParentAction,
          leading: Icon(AleraIcons.link, size: 16),
          label: 'Set Parent Workspace',
        ),
        if (widget.onClearParent != null)
          const AleraDropdownEntry<String>(
            value: _clearParentAction,
            leading: Icon(AleraIcons.close, size: 16),
            label: 'Clear Parent Workspace',
          ),
        const PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry<String>(
          value: _openFolderAction,
          leading: const Icon(
            AleraIcons.folderOpen,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Open in ${widget.fileManagerLabel}',
        ),
        const AleraDropdownEntry<String>(
          value: _copyPathAction,
          leading: Icon(
            AleraIcons.copy,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Copy Path',
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<String>(
          value: _sleepAction,
          leading: Icon(
            AleraIcons.theme,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Sleep',
        ),
        AleraDropdownEntry<String>(
          value: _removeAction,
          leading: Icon(
            AleraIcons.delete,
            size: 16,
            color: widget.onDelete != null
                ? AleraTokens.foreground
                : AleraTokens.foregroundFaint,
          ),
          label: 'Remove',
          enabled: widget.onDelete != null,
        ),
      ],
    );

    if (selected == _renameAction) {
      widget.onRename();
    } else if (selected == _manageTagsAction) {
      widget.onManageTags();
    } else if (selected == _setParentAction) {
      widget.onSetParent();
    } else if (selected == _clearParentAction) {
      widget.onClearParent?.call();
    } else if (selected == _openFolderAction) {
      widget.onOpenFolder();
    } else if (selected == _copyPathAction) {
      widget.onCopyPath();
    } else if (selected == _sleepAction) {
      widget.onSleep();
    } else if (selected == _removeAction) {
      widget.onDelete?.call();
    }
  }

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
    final branchLabel = _buildBranchLabel();
    final tags = _tagLabels();
    final hostId = _remoteHostId();
    final hasAgents = widget.agentRuns.isNotEmpty;
    final showProject = widget.showProject;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
          child: AnimatedContainer(
            duration: AleraTokens.durationMid,
            decoration: BoxDecoration(
              color: isActive
                  ? AleraTokens.surfaceElevated
                  : (_hovered ? AleraTokens.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: InkWell(
              key: ValueKey<String>('workspace-row:${widget.workspace.path}'),
              onTap: widget.onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                  vertical: AleraTokens.space6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox.square(
                          dimension: _statusSlotSize,
                          child: Center(
                            child: widget.status == null
                                ? AleraStatusDot(
                                    active: isActive || widget.hasTerminalTabs,
                                  )
                                : AgentRunStateIndicator(
                                    status: widget.status!,
                                    size: _statusSlotSize - 1,
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
                                    widget.workspace.name,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AleraTokens.foreground,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
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
                                if (WorkspaceRoleBadge.hasRole(
                                  widget.workspace,
                                )) ...<Widget>[
                                  const SizedBox(width: AleraTokens.space6),
                                  const Tooltip(
                                    message: 'Default Workspace',
                                    child: Icon(
                                      AleraIcons.workspaceMain,
                                      size: 12,
                                      color: AleraTokens.foregroundMuted,
                                      key: Key('workspace-tray-home'),
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
                                if (tags.isNotEmpty) ...<Widget>[
                                  const SizedBox(width: AleraTokens.space6),
                                  Tooltip(
                                    message: tags.join(', '),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const Icon(
                                          AleraIcons.tag,
                                          size: 12,
                                          color: AleraTokens.foregroundMuted,
                                          key: Key('workspace-tray-tags'),
                                        ),
                                        const SizedBox(
                                          width: AleraTokens.space2,
                                        ),
                                        Text(
                                          '${tags.length}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color:
                                                    AleraTokens.foregroundMuted,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (hostId != null) ...<Widget>[
                                  const SizedBox(width: AleraTokens.space6),
                                  Tooltip(
                                    message: 'Host: $hostId',
                                    child: const Icon(
                                      AleraIcons.host,
                                      size: 12,
                                      color: AleraTokens.foregroundMuted,
                                      key: Key('workspace-tray-host'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
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
                            onToggleAgents: hasAgents
                                ? widget.onToggleExpanded
                                : null,
                            agentTooltip: hasAgents
                                ? _agentTrayTooltip(
                                    runs: widget.agentRuns,
                                    expanded: widget.expanded,
                                  )
                                : null,
                          ),
                        ],
                      ],
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
    return _agentRunDescription(runs.single.status);
  }
  return 'Show Agent Runs';
}

/// Right-side icon tray for expandable controls: agents and children.
class _WorkspaceIconTray extends StatelessWidget {
  const _WorkspaceIconTray({
    required this.visibleChildCount,
    required this.childrenCollapsed,
    required this.onToggleChildren,
    required this.agentGroups,
    required this.agentsExpanded,
    required this.onToggleAgents,
    required this.agentTooltip,
  });

  final int visibleChildCount;
  final bool childrenCollapsed;
  final VoidCallback? onToggleChildren;
  final List<WorkspaceAgentRunGroup> agentGroups;
  final bool agentsExpanded;
  final VoidCallback? onToggleAgents;
  final String? agentTooltip;

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
            mainAxisSize: MainAxisSize.min,
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
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (index, item) in items.indexed) ...<Widget>[
          if (index > 0) const SizedBox(width: AleraTokens.space6),
          item,
        ],
      ],
    );
  }
}

class _TrayIconItem extends StatelessWidget {
  const _TrayIconItem({
    super.key,
    required this.tooltip,
    required this.child,
    this.onTap,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onTap;

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
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: content,
            ),
    );
  }
}

class _WorkspaceAgentRunList extends StatelessWidget {
  const _WorkspaceAgentRunList({
    required this.workspace,
    required this.runs,
    required this.workspaceIsActive,
    required this.activeTabId,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
  });

  final Workspace workspace;
  final List<WorkspaceAgentRun> runs;
  final bool workspaceIsActive;
  final String? activeTabId;
  final _TerminalTabCallback onSelectTerminal;
  final _TerminalTabCallback onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final run in runs)
          _AgentRunRow(
            tab: run.tab,
            status: run.status,
            isActive: workspaceIsActive && activeTabId == run.tab.id,
            onTap: () => onSelectTerminal(workspace, run.tab.id),
            onClose: () => onCloseTerminal(workspace, run.tab.id),
          ),
      ],
    );
  }
}
