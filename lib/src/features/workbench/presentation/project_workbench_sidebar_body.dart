part of 'project_workbench_sidebar.dart';

class const _SidebarBody({
  required final WorkbenchState state,
  required final WorkbenchController controller,
  required final List<WorkbenchSidebarRow> rows,
  required final Map<String, SshTarget> sshTargets,
  required final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace,
  required final Future<void> Function(Workspace workspace)
  onOpenWorkspaceFolder,
  required final Future<void> Function(Workspace workspace) onCopyWorkspacePath,
  required final Future<void> Function(Workspace workspace)
  onOpenWorkspaceInBrowser,
  required final Future<void> Function(Workspace workspace) onSleepWorkspace,
  required final Future<void> Function(Workspace workspace)
  onToggleWorkspaceArchived,
  required final Future<void> Function(Project project) onCreateWorkspace,
  required final Future<void> Function(Project project) onOpenProjectSettings,
  required final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace,
  required final Future<void> Function(Workspace workspace) onHandOffWorkspace,
  required final Future<void> Function(Project project, Workspace workspace)
  onHandOnWorkspace,
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
      final panel = state.workspacePanelFor(row.workspace.id);
      final mainTabIds = <String>{
        for (final key in panel.mainKeys)
          if (WorkspacePanel.tabId(key) case final String id) id,
      };
      final mainRuns = row.agentRuns
          .where((run) => mainTabIds.contains(run.tab.id))
          .toList();
      final rightRuns = row.agentRuns
          .where((run) => !mainTabIds.contains(run.tab.id))
          .toList();
      final mergeMainAgent = mainRuns.length <= 1;
      final primaryRun = mergeMainAgent ? mainRuns.firstOrNull : null;
      final secondaryRuns = <WorkspaceAgentRun>[
        if (!mergeMainAgent) ...mainRuns,
        ...rightRuns,
      ];
      final leftPadding = _indentPadding(row.indent);
      final workspaces = [
        for (final group in state.workspacesByProject.values) ...group,
      ];
      final hasDescendants = workspaceIdsDescendedFrom(
        workspaces,
        row.workspace.id,
      ).isNotEmpty;
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _WorkspaceRow(
          project: row.project,
          workspace: row.workspace,
          hostTarget: sshTargets[row.workspace.hostId.trim()],
          agentRuns: secondaryRuns,
          agentRunGroups: groupWorkspaceAgentRuns(secondaryRuns),
          status: primaryRun?.status,
          primaryStatus: primaryRun?.status,
          hasTerminalTabs: row.hasTerminalTabs,
          isActive: row.workspace.id == state.activeWorkspaceId,
          activeTabId: WorkspacePanel.tabId(panel.focusedKey),
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
          onToggleArchived: state.supportsArchive
              ? () => onToggleWorkspaceArchived(row.workspace)
              : null,
          onToggleExpanded: () =>
              controller.toggleWorkspaceExpanded(row.workspace.id),
          fileManagerLabel: fileManagerLabel,
          onRename: () => onRenameWorkspace(row.workspace),
          onSetPinned: () =>
              onSetWorkspacePinned(row.workspace, !row.workspace.isPinned),
          onPinWorkspaceTree: hasDescendants
              ? () => onSetWorkspaceTreePinned(row.workspace, true)
              : null,
          onUnpinWorkspaceTree: hasDescendants
              ? () => onSetWorkspaceTreePinned(row.workspace, false)
              : null,
          onManageTags: () => onManageWorkspaceTags(row.workspace),
          sections: state.sections,
          hasTreeSection: workspaceTreeHasSection(workspaces, row.workspace.id),
          onSetSection: state.supportsSections
              ? (target, create) => showWorkspaceSectionDialog(
                  context,
                  controller,
                  row.workspace,
                  applyToTree: target == _SectionTarget.tree,
                  createMode: create,
                )
              : null,
          onClearSection: state.supportsSections
              ? (target) => unawaited(
                  _saveWorkspaceSection(
                    context,
                    controller,
                    row.workspace,
                    tree: target == _SectionTarget.tree,
                  ),
                )
              : null,
          onAssignSection: state.supportsSections
              ? (target, sectionId) => unawaited(
                  _saveWorkspaceSection(
                    context,
                    controller,
                    row.workspace,
                    tree: target == _SectionTarget.tree,
                    sectionId: sectionId,
                  ),
                )
              : null,
          onSetParent: () => onSetWorkspaceParent(row.workspace),
          onClearParent: row.workspace.hasParentWorkspace
              ? () => onClearWorkspaceParent(row.workspace)
              : null,
          onSelectTerminal: onSelectTerminal,
          onCloseTerminal: onCloseTerminal,
          onDelete: () => onDeleteWorkspace(row.project, row.workspace),
          onHandOff:
              row.workspace.isMain && row.project.supportsLinkedWorkspaces
              ? () => unawaited(onHandOffWorkspace(row.workspace))
              : null,
          onHandOn:
              !row.workspace.isMain && row.project.supportsLinkedWorkspaces
              ? () => unawaited(onHandOnWorkspace(row.project, row.workspace))
              : null,
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
