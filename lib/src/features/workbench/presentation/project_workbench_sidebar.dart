import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_collapsed_rail.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_resize_handle.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_search_bar.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workbench_sidebar_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

typedef _TerminalTabCallback = void Function(Workspace workspace, String tabId);

class ProjectWorkbenchSidebar extends ConsumerStatefulWidget {
  const ProjectWorkbenchSidebar({super.key});

  @override
  ConsumerState<ProjectWorkbenchSidebar> createState() =>
      _ProjectWorkbenchSidebarState();
}

class _ProjectWorkbenchSidebarState
    extends ConsumerState<ProjectWorkbenchSidebar> {
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workbenchControllerProvider);
    final agentStatuses = ref.watch(agentStatusControllerProvider);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final workspaceFolderOpener = ref.read(workspaceFolderOpenerProvider);
    if (state.collapsed) {
      return _CollapsedSidebar(
        state: state,
        controller: controller,
        onAddProject: _addProject,
        onOpenSettings: () => unawaited(_openSettings()),
      );
    }
    return SizedBox(
      width: state.sidebarWidth,
      child: Stack(
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              color: AleraTokens.surfaceVariant,
              border: Border(
                right: BorderSide(color: AleraTokens.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SidebarBrandRow(
                  collapsed: false,
                  onToggleCollapsed: () =>
                      controller.setCollapsed(!state.collapsed),
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                SidebarSearchBar(
                  initialQuery: state.searchQuery,
                  focusNode: _searchFocus,
                  onChanged: controller.setSearchQuery,
                  hintText: 'Search workspaces',
                ),
                WorkbenchSidebarToolbar(
                  onAddWorkspace: _createWorkspaceForActiveProject,
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                Expanded(
                  child: state.projects.isEmpty
                      ? _EmptyProjectsView(onAddProject: _addProject)
                      : _SidebarBody(
                          state: state,
                          controller: controller,
                          agentStatuses: agentStatuses,
                          onOpenWorkspace: _openWorkspace,
                          onOpenWorkspaceFolder: _openWorkspaceFolder,
                          onCopyWorkspacePath: _copyWorkspacePath,
                          onSleepWorkspace: _sleepWorkspace,
                          onCreateWorkspace: _createWorkspace,
                          onDeleteWorkspace: _deleteWorkspace,
                          onRenameProject: _renameProject,
                          onRemoveProject: _removeProject,
                          onRenameWorkspace: _renameWorkspace,
                          fileManagerLabel:
                              workspaceFolderOpener.fileManagerLabel,
                          onSelectTerminal: _selectTerminal,
                          onCloseTerminal: _closeTerminal,
                        ),
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                _SidebarFooter(
                  onAddProject: _addProject,
                  onOpenSettings: () => unawaited(_openSettings()),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: SidebarResizeHandle(
              currentWidth: state.sidebarWidth,
              onResize: controller.setSidebarWidth,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createWorkspaceForActiveProject() async {
    final state = ref.read(workbenchControllerProvider);
    if (state.projects.isEmpty) {
      return;
    }
    final activeProject = state.activeProject;
    await _createWorkspace(
      activeProject?.supportsLinkedWorkspaces == true ? activeProject : null,
    );
  }

  Future<void> _addProject() => showAddProjectFlow(context, ref);

  Future<void> _openSettings() => openSettingsDialog(context);

  Future<void> _createWorkspace(Project? initialProject) {
    return showCreateWorkspaceFlow(
      context,
      ref,
      initialProject: initialProject,
    );
  }

  Future<void> _openWorkspace(Project project, Workspace workspace) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    await controller.selectWorkspace(project: project, workspace: workspace);
  }

  Future<void> _openWorkspaceFolder(Workspace workspace) async {
    final result = await ref
        .read(workspaceFolderOpenerProvider)
        .open(workspace.path);
    if (!result.ok && mounted) {
      AleraToast.show(
        context,
        message: result.message ?? 'Could not open workspace folder.',
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _copyWorkspacePath(Workspace workspace) async {
    await Clipboard.setData(ClipboardData(text: workspace.path));
    if (!mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Workspace path copied',
      tone: AleraToastTone.success,
    );
  }

  void _sleepWorkspace(Workspace workspace) {
    ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
    AleraToast.show(
      context,
      message: 'Workspace slept',
      tone: AleraToastTone.success,
    );
  }

  Future<void> _renameProject(Project project) async {
    final name = await showRenameDialog(
      context,
      title: 'Rename project',
      labelText: 'Project name',
      initialValue: project.name,
      confirmLabel: 'Rename',
    );
    if (name == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .renameProject(projectId: project.id, name: name);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project renamed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _renameWorkspace(Workspace workspace) async {
    final name = await showRenameDialog(
      context,
      title: 'Rename workspace',
      labelText: 'Workspace name',
      initialValue: workspace.name,
      confirmLabel: 'Rename',
    );
    if (name == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .renameWorkspace(workspaceId: workspace.id, name: name);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Workspace renamed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _deleteWorkspace(Project project, Workspace workspace) async {
    if (workspace.isMain) {
      return;
    }
    final branch = workspace.branch;
    final shouldConfirm = ref
        .read(settingsControllerProvider)
        .general
        .confirmWorkspaceRemoval;
    final confirmed = shouldConfirm
        ? await showDialog<bool>(
            context: context,
            builder: (_) => AleraConfirmDialog(
              title: 'Remove workspace?',
              message: branch == null || branch.isEmpty
                  ? 'This removes the worktree for "${workspace.name}".'
                  : 'This removes the worktree for "${workspace.name}" and deletes '
                        'branch "$branch".',
              confirmLabel: 'Remove',
              destructive: true,
            ),
          )
        : true;
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .deleteWorkspace(project: project, workspace: workspace);
      // Only dispose the live terminal sessions once the worktree was actually
      // removed, so a failed git removal doesn't orphan a still-valid workspace.
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Workspace removed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _removeProject(Project project) async {
    final shouldConfirm = ref
        .read(settingsControllerProvider)
        .general
        .confirmProjectRemoval;
    final confirmed = shouldConfirm
        ? await showDialog<bool>(
            context: context,
            builder: (_) => AleraConfirmDialog(
              title: 'Remove project?',
              message:
                  'This unregisters "${project.name}" and deletes its workspace '
                  'metadata. Repository files on disk are not deleted.',
              confirmLabel: 'Remove',
              destructive: true,
            ),
          )
        : true;
    if (confirmed != true || !mounted) {
      return;
    }
    final runtime = ref.read(terminalRuntimeProvider);
    final workspaces = ref
        .read(workbenchControllerProvider)
        .workspacesFor(project.id);
    for (final workspace in workspaces) {
      runtime.closeWorkspace(workspace.id);
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .removeProject(project.id);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project removed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _selectTerminal(Workspace workspace, String tabId) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final state = ref.read(workbenchControllerProvider);
    if (state.activeWorkspaceId != workspace.id) {
      Project? project;
      for (final candidate in state.projects) {
        if (candidate.id == workspace.projectId) {
          project = candidate;
          break;
        }
      }
      if (project != null) {
        await controller.selectWorkspace(
          project: project,
          workspace: workspace,
        );
      }
    }
    controller.setActiveTab(workspaceId: workspace.id, tabId: tabId);
    WorkspaceTabRecord? tabRecord;
    for (final tab
        in ref.read(workbenchControllerProvider).tabsFor(workspace.id)) {
      if (tab.id == tabId) {
        tabRecord = tab;
        break;
      }
    }
    if (tabRecord == null) {
      return;
    }
    ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: workspace, tab: tabRecord)
        .requestFocus();
  }

  Future<void> _closeTerminal(Workspace workspace, String tabId) async {
    ref.read(terminalRuntimeProvider).closeTab(tabId);
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .closeWorkspaceTab(workspace: workspace, tabId: tabId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }
}

class _CollapsedSidebar extends StatelessWidget {
  const _CollapsedSidebar({
    required this.state,
    required this.controller,
    required this.onAddProject,
    required this.onOpenSettings,
  });

  final WorkbenchState state;
  final WorkbenchController controller;
  final VoidCallback onAddProject;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final workspaceCounts = <String, int>{
      for (final project in state.projects)
        project.id: state.workspacesFor(project.id).length,
    };
    return SizedBox(
      width: AleraTokens.sidebarCollapsedWidth,
      child: Container(
        decoration: const BoxDecoration(
          color: AleraTokens.surfaceVariant,
          border: Border(right: BorderSide(color: AleraTokens.borderSubtle)),
        ),
        child: Column(
          children: <Widget>[
            SidebarBrandRow(
              collapsed: true,
              onToggleCollapsed: () =>
                  controller.setCollapsed(!state.collapsed),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: SidebarCollapsedRail(
                projects: state.projects,
                activeProjectId: state.activeProjectId,
                workspaceCountByProject: workspaceCounts,
                onSelectProject: (project) {
                  controller.setCollapsed(false);
                  unawaited(controller.activateProject(project));
                },
                onAddProject: onAddProject,
              ),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            _CollapsedSidebarFooter(onOpenSettings: onOpenSettings),
          ],
        ),
      ),
    );
  }
}

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
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _WorkspaceRow(
          project: row.project,
          workspace: row.workspace,
          agentRunCount: agentRuns.length,
          status: agentRuns.isEmpty ? null : agentRuns.first.status,
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

class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow({
    required this.project,
    required this.workspace,
    required this.agentRunCount,
    required this.status,
    required this.isActive,
    required this.showProjectChip,
    required this.expanded,
    required this.onTap,
    required this.onOpenFolder,
    required this.onCopyPath,
    required this.onSleep,
    required this.onToggleExpanded,
    required this.fileManagerLabel,
    required this.onRename,
    this.onDelete,
  });

  final Project project;
  final Workspace workspace;
  final int agentRunCount;
  final AgentStatusEntry? status;
  final bool isActive;
  final bool showProjectChip;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyPath;
  final VoidCallback onSleep;
  final VoidCallback onToggleExpanded;
  final String fileManagerLabel;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  static const String _renameAction = 'rename';
  static const String _openFolderAction = 'open-folder';
  static const String _copyPathAction = 'copy-path';
  static const String _sleepAction = 'sleep';
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
          leading: Icon(Icons.edit_outlined, size: 16),
          label: 'Rename',
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry<String>(
          value: _openFolderAction,
          leading: const Icon(
            Icons.folder_open,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Open in ${widget.fileManagerLabel}',
        ),
        const AleraDropdownEntry<String>(
          value: _copyPathAction,
          leading: Icon(Icons.copy, size: 16, color: AleraTokens.foreground),
          label: 'Copy path',
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<String>(
          value: _sleepAction,
          leading: Icon(
            Icons.bedtime_outlined,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Sleep',
        ),
        AleraDropdownEntry<String>(
          value: _removeAction,
          leading: Icon(
            Icons.delete_outline,
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

  String _buildSecondaryLine() {
    final branch = widget.workspace.branch;
    final parts = <String>[
      if (branch != null && branch.isNotEmpty)
        branch
      else if (widget.project.isFolder)
        'Local folder'
      else
        'Git repository',
    ];
    final source = widget.workspace.sourceBranch;
    if (!widget.workspace.isMain && source != null && source.isNotEmpty) {
      parts.add('base: $source');
    }
    if (widget.agentRunCount > 0) {
      parts.add(
        widget.agentRunCount == 1
            ? '1 agent run'
            : '${widget.agentRunCount} agent runs',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
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
                          ? AleraStatusDot(active: isActive)
                          : _AgentRunStateIndicator(status: widget.status!),
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
                              if (widget.workspace.isMain) ...<Widget>[
                                const SizedBox(width: AleraTokens.space6),
                                const AleraBadge(label: 'primary'),
                              ],
                            ],
                          ),
                          const SizedBox(height: AleraTokens.space4),
                          Row(
                            children: <Widget>[
                              if (widget.showProjectChip) ...<Widget>[
                                Flexible(
                                  child: AleraChip(label: widget.project.name),
                                ),
                                const SizedBox(width: AleraTokens.space6),
                              ],
                              Flexible(
                                child: Text(
                                  _buildSecondaryLine(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AleraTokens.foregroundFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.agentRunCount > 0)
                      AleraIconButton(
                        tooltip: widget.expanded
                            ? 'Hide agent runs'
                            : 'Show agent runs',
                        onPressed: widget.onToggleExpanded,
                        icon: widget.expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        iconSize: 14,
                        minSize: 24,
                      ),
                    if (widget.onDelete != null)
                      IgnorePointer(
                        ignoring: !actionsVisible,
                        child: AnimatedOpacity(
                          opacity: actionsVisible ? 1 : 0,
                          duration: AleraTokens.durationFast,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: AleraTokens.space2,
                            ),
                            child: AleraIconButton(
                              tooltip: 'Remove workspace',
                              onPressed: widget.onDelete!,
                              icon: Icons.delete_outline,
                              iconSize: 14,
                              minSize: 24,
                            ),
                          ),
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

class _AgentRunRow extends StatefulWidget {
  const _AgentRunRow({
    required this.workspace,
    required this.tab,
    required this.status,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final AgentStatusEntry status;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_AgentRunRow> createState() => _AgentRunRowState();
}

class _AgentRunRowState extends State<_AgentRunRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
    final primaryLabel = _agentRunPrimaryLabel(widget.status);
    final secondaryLabel = _agentRunSecondaryLabel(widget.status);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          decoration: BoxDecoration(
            color: isActive
                ? AleraTokens.surfaceElevated
                : (_hovered ? AleraTokens.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
          child: InkWell(
            onTap: widget.onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: _AgentRunStateIndicator(
                      status: widget.status,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AgentIdentityIcon(
                      agentType: widget.status.agentType,
                      size: 13,
                      color: isActive
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          primaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isActive
                                ? AleraTokens.foreground
                                : AleraTokens.foregroundMuted,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (secondaryLabel.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AleraTokens.space2),
                          Text(
                            secondaryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AleraTokens.foregroundFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IgnorePointer(
                    ignoring: !actionsVisible,
                    child: AnimatedOpacity(
                      opacity: actionsVisible ? 1 : 0,
                      duration: AleraTokens.durationFast,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: AleraTokens.space4,
                        ),
                        child: AleraIconButton(
                          tooltip: 'Close terminal',
                          onPressed: widget.onClose,
                          icon: Icons.close,
                          iconSize: 12,
                          minSize: 22,
                          borderRadius: AleraTokens.radiusSm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentRunStateIndicator extends StatelessWidget {
  const _AgentRunStateIndicator({required this.status, this.size = 13});

  final AgentStatusEntry status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = _agentRunStateLabel(status);
    final color = _agentRunStateColor(status);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: _buildIndicator(color)),
        ),
      ),
    );
  }

  Widget _buildIndicator(Color color) {
    if (status.state == AgentStatusState.working) {
      return SizedBox.square(
        dimension: size - 2,
        child: CircularProgressIndicator(
          strokeWidth: 1.7,
          color: AleraTokens.warning,
        ),
      );
    }
    final icon = status.interrupted == true
        ? Icons.cancel_outlined
        : switch (status.state) {
            AgentStatusState.done => Icons.check_circle_outline,
            AgentStatusState.waiting ||
            AgentStatusState.blocked => Icons.notifications_active_outlined,
            AgentStatusState.working => Icons.sync,
          };
    return Icon(icon, size: size, color: color);
  }
}

Color _agentRunStateColor(AgentStatusEntry status) {
  if (status.interrupted == true) {
    return AleraTokens.error;
  }
  return switch (status.state) {
    AgentStatusState.working => AleraTokens.warning,
    AgentStatusState.waiting => AleraTokens.warning,
    AgentStatusState.blocked => AleraTokens.error,
    AgentStatusState.done => AleraTokens.success,
  };
}

String _agentRunStateLabel(AgentStatusEntry status) {
  if (status.interrupted == true) {
    return 'Interrupted';
  }
  return switch (status.state) {
    AgentStatusState.working => 'Working',
    AgentStatusState.waiting => 'Waiting for input',
    AgentStatusState.blocked => 'Blocked',
    AgentStatusState.done => 'Done',
  };
}

String _agentRunPrimaryLabel(AgentStatusEntry status) {
  final prompt = status.prompt.trim();
  if (prompt.isNotEmpty) {
    return prompt;
  }
  return _agentRunStateLabel(status);
}

String _agentRunSecondaryLabel(AgentStatusEntry status) {
  if (status.state == AgentStatusState.working) {
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
  return '${agentDisplayName(status.agentType)} · ${_agentRunStateLabel(status)}';
}

class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView({required this.onAddProject});

  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: Icons.folder_outlined,
      title: 'No projects yet',
      message: 'Add a git repository to create workspaces with terminal tabs.',
      action: FilledButton.icon(
        onPressed: onAddProject,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add your first project'),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.onAddProject,
    required this.onOpenSettings,
  });

  final VoidCallback onAddProject;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AleraTokens.surface),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onAddProject,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add project'),
              ),
              const Spacer(),
              _FooterIconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                icon: Icons.settings_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedSidebarFooter extends StatelessWidget {
  const _CollapsedSidebarFooter({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AleraTokens.surface),
        child: Center(
          child: _FooterIconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: Icons.settings_outlined,
          ),
        ),
      ),
    );
  }
}

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      iconSize: 15,
      backgroundColor: AleraTokens.surfaceVariant,
      borderColor: AleraTokens.borderSubtle,
    );
  }
}
