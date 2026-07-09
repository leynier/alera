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
    required this.showProjectChip,
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
  final bool showProjectChip;
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
  static const int _maxInlineTags = 3;
  static const String _renameAction = 'rename';
  static const String _openFolderAction = 'open-folder';
  static const String _copyPathAction = 'copy-path';
  static const String _sleepAction = 'sleep';
  static const String _manageTagsAction = 'manage-tags';
  static const String _setParentAction = 'set-parent';
  static const String _clearParentAction = 'clear-parent';
  static const String _removeAction = 'remove';

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

  List<Widget> _buildMetadataChips() {
    final branchLabel = _buildBranchLabel();
    final tags = _tagLabels();
    final chips = <Widget>[
      if (widget.showProjectChip)
        AleraChip(
          leading: AleraIcons.folderSpecial,
          label: widget.project.name,
          tooltip: widget.project.name,
        ),
      AleraChip(
        leading: AleraIcons.gitBranch,
        label: branchLabel,
        tooltip: branchLabel,
      ),
      for (final tag in tags.take(_maxInlineTags))
        AleraChip(leading: AleraIcons.tag, label: '#$tag', tooltip: tag),
    ];
    final hiddenTags = tags.skip(_maxInlineTags).toList(growable: false);
    if (hiddenTags.isNotEmpty) {
      chips.add(
        AleraChip(
          leading: AleraIcons.tag,
          label: '+${hiddenTags.length} Tags',
          tooltip: hiddenTags.join(', '),
        ),
      );
    }
    final hostId = widget.workspace.hostId.trim();
    if (hostId.isNotEmpty && hostId != 'local') {
      chips.add(
        AleraChip(
          leading: AleraIcons.host,
          label: hostId,
          tooltip: 'Host: $hostId',
        ),
      );
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
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
              onTap: widget.onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                  vertical: AleraTokens.space8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: widget.status == null
                          ? AleraStatusDot(
                              active: isActive || widget.hasTerminalTabs,
                            )
                          : AgentRunStateIndicator(status: widget.status!),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  widget.workspace.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AleraTokens.foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (WorkspaceRoleBadge.hasRole(
                                widget.workspace,
                              )) ...<Widget>[
                                const SizedBox(width: AleraTokens.space6),
                                WorkspaceRoleBadge(workspace: widget.workspace),
                              ],
                            ],
                          ),
                          const SizedBox(height: AleraTokens.space4),
                          Wrap(
                            spacing: AleraTokens.space6,
                            runSpacing: AleraTokens.space4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: _buildMetadataChips(),
                          ),
                          if (widget.agentRuns.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AleraTokens.space6),
                            _WorkspaceAgentSection(
                              workspace: widget.workspace,
                              runs: widget.agentRuns,
                              groups: widget.agentRunGroups,
                              expanded: widget.expanded,
                              workspaceIsActive: widget.isActive,
                              activeTabId: widget.activeTabId,
                              onToggleExpanded: widget.onToggleExpanded,
                              onSelectTerminal: widget.onSelectTerminal,
                              onCloseTerminal: widget.onCloseTerminal,
                            ),
                          ],
                          if (widget.visibleChildCount > 0 &&
                              widget.onToggleChildren != null) ...<Widget>[
                            const SizedBox(height: AleraTokens.space6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AleraChip(
                                leading: AleraIcons.workspaceChildren,
                                label: widget.visibleChildCount == 1
                                    ? '1 child'
                                    : '${widget.visibleChildCount} children',
                                trailing: widget.childrenCollapsed
                                    ? AleraIcons.chevronRight
                                    : AleraIcons.chevronDown,
                                tooltip: widget.childrenCollapsed
                                    ? 'Show Child Workspaces'
                                    : 'Hide Child Workspaces',
                                onTap: widget.onToggleChildren,
                              ),
                            ),
                          ],
                        ],
                      ),
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
}

class _WorkspaceAgentSection extends StatelessWidget {
  const _WorkspaceAgentSection({
    required this.workspace,
    required this.runs,
    required this.groups,
    required this.expanded,
    required this.workspaceIsActive,
    required this.activeTabId,
    required this.onToggleExpanded,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
  });

  final Workspace workspace;
  final List<WorkspaceAgentRun> runs;
  final List<WorkspaceAgentRunGroup> groups;
  final bool expanded;
  final bool workspaceIsActive;
  final String? activeTabId;
  final VoidCallback onToggleExpanded;
  final _TerminalTabCallback onSelectTerminal;
  final _TerminalTabCallback onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    if (runs.length == 1) {
      final run = runs.single;
      return _AgentRunRow(
        tab: run.tab,
        status: run.status,
        isActive: workspaceIsActive && activeTabId == run.tab.id,
        onTap: () => onSelectTerminal(workspace, run.tab.id),
        onClose: () => onCloseTerminal(workspace, run.tab.id),
      );
    }
    if (!expanded) {
      return WorkspaceAgentCompactSummary(
        groups: groups,
        expanded: expanded,
        onToggle: onToggleExpanded,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WorkspaceAgentCompactSummary(
          groups: groups,
          expanded: expanded,
          onToggle: onToggleExpanded,
        ),
        const SizedBox(height: AleraTokens.space2),
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
