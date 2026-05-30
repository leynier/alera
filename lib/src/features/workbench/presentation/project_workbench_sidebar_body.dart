part of 'project_workbench_sidebar.dart';

class _SidebarBody extends StatelessWidget {
  const _SidebarBody({
    required this.state,
    required this.controller,
    required this.agentStatuses,
    required this.onOpenWorkspace,
    required this.onOpenWorkspaceFolder,
    required this.onCopyWorkspacePath,
    required this.onSleepWorkspace,
    required this.onCreateWorkspace,
    required this.onDeleteWorkspace,
    required this.onRenameProject,
    required this.onRemoveProject,
    required this.onRenameWorkspace,
    required this.fileManagerLabel,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
  });

  final WorkbenchState state;
  final WorkbenchController controller;
  final Map<String, AgentStatusEntry> agentStatuses;
  final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace;
  final Future<void> Function(Workspace workspace) onOpenWorkspaceFolder;
  final Future<void> Function(Workspace workspace) onCopyWorkspacePath;
  final void Function(Workspace workspace) onSleepWorkspace;
  final Future<void> Function(Project project) onCreateWorkspace;
  final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace;
  final Future<void> Function(Project project) onRenameProject;
  final Future<void> Function(Project project) onRemoveProject;
  final Future<void> Function(Workspace workspace) onRenameWorkspace;
  final String fileManagerLabel;
  final _TerminalTabCallback onSelectTerminal;
  final _TerminalTabCallback onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    final rows = buildSidebarRows(state, agentStatuses: agentStatuses);
    if (rows.isEmpty) {
      return _EmptyResultsView(query: state.searchQuery);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AleraTokens.space4,
        bottom: AleraTokens.space8,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return _buildRow(row);
      },
    );
  }

  Widget _buildRow(WorkbenchSidebarRow row) {
    if (row is WorkbenchProjectHeaderRow) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space2,
        ),
        child: _ProjectHeaderTile(
          project: row.project,
          expanded: !row.collapsed,
          workspaceCount: row.workspaceCount,
          onToggle: () => controller.toggleProjectCollapsed(row.project.id),
          onCreateWorkspace: row.project.supportsLinkedWorkspaces
              ? () => onCreateWorkspace(row.project)
              : null,
          onRenameProject: () => onRenameProject(row.project),
          onRemoveProject: () => onRemoveProject(row.project),
        ),
      );
    }
    if (row is WorkbenchWorkspaceRow) {
      final leftPadding = row.indent == 0
          ? AleraTokens.space8
          : AleraTokens.space20;
      final tabs = state.tabsFor(row.workspace.id);
      final agentRuns = visibleWorkspaceAgentRuns(
        tabs: tabs,
        agentStatuses: agentStatuses,
      );
      final hasTerminalTabs = tabs.any(
        (tab) => tab.kind == WorkspaceTabKind.terminal,
      );
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _WorkspaceRow(
          project: row.project,
          workspace: row.workspace,
          agentRunCount: agentRuns.length,
          status: agentRuns.isEmpty ? null : agentRuns.first.status,
          hasTerminalTabs: hasTerminalTabs,
          isActive: row.workspace.id == state.activeWorkspaceId,
          showProjectChip: row.showProjectChip,
          expanded: row.expanded,
          onTap: () => onOpenWorkspace(row.project, row.workspace),
          onOpenFolder: () => unawaited(onOpenWorkspaceFolder(row.workspace)),
          onCopyPath: () => unawaited(onCopyWorkspacePath(row.workspace)),
          onSleep: () => onSleepWorkspace(row.workspace),
          onToggleExpanded: () =>
              controller.toggleWorkspaceExpanded(row.workspace.id),
          fileManagerLabel: fileManagerLabel,
          onRename: () => onRenameWorkspace(row.workspace),
          onDelete: row.workspace.isMain
              ? null
              : () => onDeleteWorkspace(row.project, row.workspace),
        ),
      );
    }
    if (row is SidebarAgentRunRow) {
      final leftPadding = row.indent <= 1
          ? AleraTokens.space20
          : AleraTokens.space32;
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _AgentRunRow(
          workspace: row.workspace,
          tab: row.tab,
          status: row.status,
          // An agent run only reads as active when its workspace and backing
          // terminal tab are both selected.
          isActive:
              row.workspace.id == state.activeWorkspaceId &&
              state.activeTabIdByWorkspace[row.workspace.id] == row.tab.id,
          onTap: () => onSelectTerminal(row.workspace, row.tab.id),
          onClose: () => onCloseTerminal(row.workspace, row.tab.id),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _EmptyResultsView extends StatelessWidget {
  const _EmptyResultsView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final trimmed = query.trim();
    final message = trimmed.isEmpty
        ? 'No workspaces match the current filters'
        : 'No workspaces match "$trimmed"';
    return AleraEmptyState(message: message);
  }
}

class _ProjectHeaderTile extends StatefulWidget {
  const _ProjectHeaderTile({
    required this.project,
    required this.expanded,
    required this.workspaceCount,
    required this.onToggle,
    required this.onCreateWorkspace,
    required this.onRenameProject,
    required this.onRemoveProject,
  });

  final Project project;
  final bool expanded;
  final int workspaceCount;
  final VoidCallback onToggle;
  final VoidCallback? onCreateWorkspace;
  final VoidCallback onRenameProject;
  final VoidCallback onRemoveProject;

  @override
  State<_ProjectHeaderTile> createState() => _ProjectHeaderTileState();
}

class _ProjectHeaderTileState extends State<_ProjectHeaderTile> {
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
          value: 'rename',
          leading: Icon(Icons.edit_outlined, size: 16),
          label: 'Rename',
        ),
        AleraDropdownEntry<String>(
          value: 'new-workspace',
          leading: Icon(
            Icons.add,
            size: 16,
            color: widget.onCreateWorkspace == null
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          label: 'New workspace',
          enabled: widget.onCreateWorkspace != null,
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<String>(
          value: 'remove',
          leading: Icon(Icons.delete_outline, size: 16),
          label: 'Remove project',
        ),
      ],
    );
    if (selected == 'rename') {
      widget.onRenameProject();
    } else if (selected == 'new-workspace') {
      widget.onCreateWorkspace?.call();
    } else if (selected == 'remove') {
      widget.onRemoveProject();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(
          onTap: widget.onToggle,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: AnimatedContainer(
            duration: AleraTokens.durationFast,
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            decoration: BoxDecoration(
              color: _hovered ? AleraTokens.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.expanded ? Icons.folder_open : Icons.folder_outlined,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    widget.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _hovered
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  widget.workspaceCount.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  widget.expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                if (widget.onCreateWorkspace != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space2),
                  AleraIconButton(
                    tooltip: 'New workspace in this project',
                    onPressed: widget.onCreateWorkspace!,
                    icon: Icons.add,
                    iconSize: 14,
                    minSize: 24,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
