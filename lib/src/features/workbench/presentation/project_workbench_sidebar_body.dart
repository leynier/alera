part of 'project_workbench_sidebar.dart';

class const _SidebarBody({
  required final WorkbenchState state,
  required final WorkbenchController controller,
  required final List<WorkbenchSidebarRow> rows,
  required final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace,
  required final Future<void> Function(Workspace workspace)
  onOpenWorkspaceFolder,
  required final Future<void> Function(Workspace workspace) onCopyWorkspacePath,
  required final Future<void> Function(Workspace workspace)
  onOpenWorkspaceInBrowser,
  required final Future<void> Function(Workspace workspace) onSleepWorkspace,
  required final Future<void> Function(Project project) onCreateWorkspace,
  required final Future<void> Function(Project project) onOpenProjectSettings,
  required final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace,
  required final Future<void> Function(Project project) onRenameProject,
  required final Future<void> Function(Project project) onRemoveProject,
  required final Future<void> Function(Workspace workspace) onRenameWorkspace,
  required final Future<void> Function(Workspace workspace, bool isPinned)
  onSetWorkspacePinned,
  required final Future<void> Function(Workspace workspace, bool isPinned)
  onSetWorkspaceTreePinned,
  required final Future<void> Function(Workspace workspace)
  onManageWorkspaceTags,
  required final Future<void> Function(Workspace workspace)
  onSetWorkspaceParent,
  required final Future<void> Function(Workspace workspace)
  onClearWorkspaceParent,
  required final String fileManagerLabel,
  required final _TerminalTabCallback onSelectTerminal,
  required final _TerminalTabCallback onCloseTerminal,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
        return KeyedSubtree(
          key: ValueKey<String>(rows[index].key),
          child: _buildRow(context, rows, index),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    List<WorkbenchSidebarRow> rows,
    int index,
  ) {
    final row = rows[index];
    if (row is WorkbenchSectionHeaderRow) {
      return _WorkspaceSectionHeader(row: row, controller: controller);
    }
    if (row is WorkbenchPinnedHeaderRow) {
      return _SidebarSectionTile(
        leadingIcon: AleraIcons.pin,
        label: 'Pinned',
        count: row.workspaceCount,
        expanded: !row.collapsed,
        onToggle: controller.togglePinnedSectionCollapsed,
      );
    }
    if (row is WorkbenchAllHeaderRow) {
      final previous = index > 0 ? rows[index - 1] : null;
      return _SidebarSectionTile(
        leadingIcon: AleraIcons.listView,
        label: 'All',
        count: row.workspaceCount,
        expanded: !row.collapsed,
        showTopDivider: previous is WorkbenchWorkspaceRow,
        onToggle: controller.toggleAllSectionCollapsed,
      );
    }
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
          onOpenProjectSettings: () =>
              unawaited(onOpenProjectSettings(row.project)),
          onRenameProject: () => onRenameProject(row.project),
          onRemoveProject: () => onRemoveProject(row.project),
        ),
      );
    }
    if (row is WorkbenchWorkspaceRow) {
      final leftPadding = _indentPadding(row.indent);
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _WorkspaceRow(
          project: row.project,
          workspace: row.workspace,
          agentRuns: row.agentRuns,
          agentRunGroups: row.agentRunGroups,
          status: row.aggregateStatus,
          hasTerminalTabs: row.hasTerminalTabs,
          isActive: row.workspace.id == state.activeWorkspaceId,
          activeTabId: state.activeTabIdByWorkspace[row.workspace.id],
          showProject: row.showProjectChip,
          expanded: row.expanded,
          visibleChildCount: row.visibleChildCount,
          childrenCollapsed: row.childrenCollapsed,
          isPinnedCopy: row.isPinnedCopy,
          onToggleChildren: row.hasVisibleChildren
              ? () =>
                    controller.toggleParentWorkspaceCollapsed(row.workspace.id)
              : null,
          onTap: () => onOpenWorkspace(row.project, row.workspace),
          onOpenFolder: () => unawaited(onOpenWorkspaceFolder(row.workspace)),
          onCopyPath: () => unawaited(onCopyWorkspacePath(row.workspace)),
          onOpenInBrowser: () =>
              unawaited(onOpenWorkspaceInBrowser(row.workspace)),
          onOpenProjectSettings: () =>
              unawaited(onOpenProjectSettings(row.project)),
          onSleep: () => onSleepWorkspace(row.workspace),
          onToggleExpanded: () =>
              controller.toggleWorkspaceExpanded(row.workspace.id),
          fileManagerLabel: fileManagerLabel,
          onRename: () => onRenameWorkspace(row.workspace),
          onSetPinned: () =>
              onSetWorkspacePinned(row.workspace, !row.workspace.isPinned),
          onPinWorkspaceTree: () =>
              onSetWorkspaceTreePinned(row.workspace, true),
          onUnpinWorkspaceTree: () =>
              onSetWorkspaceTreePinned(row.workspace, false),
          onManageTags: () => onManageWorkspaceTags(row.workspace),
          onSetSection: state.supportsSections
              ? () => showWorkspaceSectionDialog(
                  context,
                  controller,
                  row.workspace,
                )
              : null,
          onClearSection:
              state.supportsSections && row.workspace.sectionId != null
              ? () => _clearSection(context, controller, row.workspace)
              : null,
          onSetParent: () => onSetWorkspaceParent(row.workspace),
          onClearParent: row.workspace.hasParentWorkspace
              ? () => onClearWorkspaceParent(row.workspace)
              : null,
          onSelectTerminal: onSelectTerminal,
          onCloseTerminal: onCloseTerminal,
          onDelete: row.workspace.isMain
              ? null
              : () => onDeleteWorkspace(row.project, row.workspace),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// Base sidebar padding plus one row-content step per nesting level, clamped
  /// so deep trees keep usable row widths in a narrow sidebar.
  double _indentPadding(int indent) {
    const double base = AleraTokens.space8;
    const double step = AleraTokens.space12;
    const double max = base + 4 * step;
    final padding = base + indent * step;
    return padding > max ? max : padding;
  }
}

class const _EmptyResultsView({required final String query})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final trimmed = query.trim();
    final message = trimmed.isEmpty
        ? 'No workspaces match the current filters'
        : 'No workspaces match "$trimmed"';
    return AleraEmptyState(message: message);
  }
}

/// Collapsible section header for the flat sidebar groupings (Pinned / All).
/// Mirrors the project header tile so the sections read as clear boundaries.
class const _SidebarSectionTile({
  required final IconData leadingIcon,
  required final String label,
  required final int count,
  required final bool expanded,
  required final VoidCallback onToggle,
  this.showTopDivider = false,
}) extends StatefulWidget {
  /// Draws a full-width divider above the header so the end of the previous
  /// section is visually marked.
  final bool showTopDivider;

  @override
  State<_SidebarSectionTile> createState() => _SidebarSectionTileState();
}

class _SidebarSectionTileState extends State<_SidebarSectionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (widget.showTopDivider)
          const Divider(height: 1, color: AleraTokens.borderSubtle),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space2,
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              onTap: widget.onToggle,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: .circular(AleraTokens.radiusLg),
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
                      widget.leadingIcon,
                      size: 14,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _hovered
                              ? AleraTokens.foreground
                              : AleraTokens.foregroundMuted,
                          fontWeight: .w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Text(
                      widget.count.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foregroundFaint,
                        fontWeight: .w500,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    Icon(
                      widget.expanded
                          ? AleraIcons.chevronUp
                          : AleraIcons.chevronDown,
                      size: 14,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class const _ProjectHeaderTile({
  required final Project project,
  required final bool expanded,
  required final int workspaceCount,
  required final VoidCallback onToggle,
  required final VoidCallback? onCreateWorkspace,
  required final VoidCallback onOpenProjectSettings,
  required final VoidCallback onRenameProject,
  required final VoidCallback onRemoveProject,
}) extends StatefulWidget {
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
      position: .fromRect(
        .fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const AleraDropdownEntry<String>(
          value: _openProjectSettingsAction,
          leading: Icon(AleraIcons.settings, size: 16),
          label: 'Open Project Settings',
        ),
        const AleraDropdownEntry<String>(
          value: 'rename',
          leading: Icon(AleraIcons.edit, size: 16),
          label: 'Rename',
        ),
        AleraDropdownEntry<String>(
          value: 'new-workspace',
          leading: Icon(
            AleraIcons.add,
            size: 16,
            color: widget.onCreateWorkspace == null
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          label: 'New Workspace',
          enabled: widget.onCreateWorkspace != null,
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<String>(
          value: 'remove',
          leading: Icon(AleraIcons.delete, size: 16),
          label: 'Remove Project',
        ),
      ],
    );
    if (selected == _openProjectSettingsAction) {
      widget.onOpenProjectSettings();
    } else if (selected == 'rename') {
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
          borderRadius: .circular(AleraTokens.radiusLg),
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
                  widget.expanded ? AleraIcons.folderOpen : AleraIcons.folder,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    widget.project.name,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _hovered
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  widget.workspaceCount.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                    fontWeight: .w500,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  widget.expanded
                      ? AleraIcons.chevronUp
                      : AleraIcons.chevronDown,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                if (widget.onCreateWorkspace != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space2),
                  AleraIconButton(
                    tooltip: 'New Workspace in This Project',
                    onPressed: widget.onCreateWorkspace!,
                    icon: AleraIcons.add,
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
