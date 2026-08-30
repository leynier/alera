part of 'project_workbench_sidebar.dart';

class const _WorkspaceRow({
  required final Project project,
  required final Workspace workspace,
  required final List<WorkspaceAgentRun> agentRuns,
  required final List<WorkspaceAgentRunGroup> agentRunGroups,
  required final AgentStatusEntry? status,
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
  required final VoidCallback onToggleExpanded,
  required final String fileManagerLabel,
  required final VoidCallback onRename,
  required final VoidCallback onSetPinned,
  required final VoidCallback onManageTags,
  required final VoidCallback onSetParent,
  required final _TerminalTabCallback onSelectTerminal,
  required final _TerminalTabCallback onCloseTerminal,
  final int visibleChildCount = 0,
  final bool childrenCollapsed = false,
  final VoidCallback? onToggleChildren,
  final VoidCallback? onClearParent,
  final VoidCallback? onDelete,
}) extends StatefulWidget {
  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
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
      position: .fromRect(
        .fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: workspaceContextMenuEntries(
        fileManagerLabel: widget.fileManagerLabel,
        hasClearParent: widget.onClearParent != null,
        canRemove: widget.onDelete != null,
        isPinned: widget.workspace.isPinned,
      ),
    );

    if (selected == _openProjectSettingsAction) {
      widget.onOpenProjectSettings();
    } else if (selected == _renameAction) {
      widget.onRename();
    } else if (selected == _togglePinAction) {
      widget.onSetPinned();
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
    } else if (selected == _openInBrowserAction) {
      widget.onOpenInBrowser();
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
              key: ValueKey<String>(
                'workspace-row:${widget.isPinnedCopy ? 'pinned' : 'regular'}:${widget.workspace.id}',
              ),
              onTap: widget.onTap,
              mouseCursor: SystemMouseCursors.click,
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
                    Row(
                      crossAxisAlignment: .center,
                      children: <Widget>[
                        SizedBox.square(
                          dimension: _statusSlotSize,
                          child: Center(
                            // One widget type in this slot regardless of state:
                            // swapping types here destroyed the element and
                            // restarted the spinner whenever an agent started
                            // or finished.
                            child: AgentRunStateIndicator(
                              key: const ValueKey<String>(
                                'workspace-status-glyph',
                              ),
                              status: widget.status,
                              size: _statusSlotSize - 1,
                              idleDotActive: isActive || widget.hasTerminalTabs,
                            ),
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: .min,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    widget.workspace.name,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: .ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AleraTokens.foreground,
                                      fontWeight: .w600,
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
                                    message: 'Default workspace',
                                    child: Icon(
                                      AleraIcons.workspaceMain,
                                      size: 12,
                                      color: AleraTokens.foregroundMuted,
                                      key: Key('workspace-tray-home'),
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
                                      mainAxisSize: .min,
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
              borderRadius: .circular(AleraTokens.radiusSm),
              child: content,
            ),
    );
  }
}

class const _WorkspaceAgentRunList({
  required final Workspace workspace,
  required final List<WorkspaceAgentRun> runs,
  required final bool workspaceIsActive,
  required final String? activeTabId,
  required final _TerminalTabCallback onSelectTerminal,
  required final _TerminalTabCallback onCloseTerminal,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        // Keyed by tab so each row keeps its identity and state across the
        // status updates that refresh this list.
        for (final run in runs)
          _AgentRunRow(
            key: ValueKey<String>(run.tab.id),
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
