import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_collapsed_rail.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_icon_button.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_resize_handle.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_search_bar.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/widgets/primary_badge.dart';
import 'package:alera/src/features/workbench/presentation/widgets/project_chip.dart';
import 'package:alera/src/features/workbench/presentation/widgets/status_dot.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workbench_sidebar_toolbar.dart';
import 'package:alera/src/shared/presentation/dropdown_entry.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

typedef _TerminalCallback = void Function(Workspace workspace, String tabId);

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
    final controller = ref.read(workbenchControllerProvider.notifier);
    final terminalRuntime = ref.read(terminalRuntimeProvider);
    final workspaceFolderOpener = ref.read(workspaceFolderOpenerProvider);
    if (state.collapsed) {
      return _CollapsedSidebar(
        state: state,
        controller: controller,
        onAddProject: _addProject,
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
                          terminalRuntime: terminalRuntime,
                          onOpenWorkspace: _openWorkspace,
                          onOpenWorkspaceFolder: _openWorkspaceFolder,
                          onCopyWorkspacePath: _copyWorkspacePath,
                          onSleepWorkspace: _sleepWorkspace,
                          onCreateWorkspace: _createWorkspace,
                          onDeleteWorkspace: _deleteWorkspace,
                          onRemoveProject: _removeProject,
                          fileManagerLabel:
                              workspaceFolderOpener.fileManagerLabel,
                          onSelectTerminal: _selectTerminal,
                          onCloseTerminal: _closeTerminal,
                        ),
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                _SidebarFooter(onAddProject: _addProject),
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
    await _createWorkspace(state.activeProject);
  }

  Future<void> _addProject() async {
    final result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => const AddProjectDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .addProject(repoPath: result.repoPath, name: result.name);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project added',
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

  Future<void> _createWorkspace(Project? initialProject) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final projects = ref.read(workbenchControllerProvider).projects;
    if (projects.isEmpty) {
      return;
    }

    final result = await showDialog<CreateWorkspaceResult>(
      context: context,
      builder: (_) => CreateWorkspaceDialog(
        projects: projects,
        initialProject: initialProject,
        loadBranches: controller.listSourceBranches,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await controller.createWorkspace(
        project: result.project,
        sourceBranch: result.sourceBranch,
        newBranchName: result.newBranchName,
        name: result.name,
      );
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Workspace created',
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

  Future<void> _deleteWorkspace(Project project, Workspace workspace) async {
    if (workspace.isMain) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove workspace?'),
        content: Text(
          'This removes the worktree for "${workspace.name}" and deletes branch "${workspace.branch}".',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AleraTokens.error,
              foregroundColor: AleraTokens.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove project?'),
        content: Text(
          'This unregisters "${project.name}" and deletes its workspace metadata. Repository files on disk are not deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AleraTokens.error,
              foregroundColor: AleraTokens.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
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
    TerminalTabRecord? tabRecord;
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
          .closeTerminalTab(workspace: workspace, tabId: tabId);
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
  });

  final WorkbenchState state;
  final WorkbenchController controller;
  final VoidCallback onAddProject;

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
            const _CollapsedSidebarFooter(),
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
    required this.terminalRuntime,
    required this.onOpenWorkspace,
    required this.onOpenWorkspaceFolder,
    required this.onCopyWorkspacePath,
    required this.onSleepWorkspace,
    required this.onCreateWorkspace,
    required this.onDeleteWorkspace,
    required this.onRemoveProject,
    required this.fileManagerLabel,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
  });

  final WorkbenchState state;
  final WorkbenchController controller;
  final TerminalRuntime terminalRuntime;
  final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace;
  final Future<void> Function(Workspace workspace) onOpenWorkspaceFolder;
  final Future<void> Function(Workspace workspace) onCopyWorkspacePath;
  final void Function(Workspace workspace) onSleepWorkspace;
  final Future<void> Function(Project project) onCreateWorkspace;
  final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace;
  final Future<void> Function(Project project) onRemoveProject;
  final String fileManagerLabel;
  final _TerminalCallback onSelectTerminal;
  final _TerminalCallback onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    final rows = buildSidebarRows(state);
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
          onCreateWorkspace: () => onCreateWorkspace(row.project),
          onRemoveProject: () => onRemoveProject(row.project),
        ),
      );
    }
    if (row is WorkbenchWorkspaceRow) {
      final leftPadding = row.indent == 0
          ? AleraTokens.space8
          : AleraTokens.space20;
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _WorkspaceRow(
          project: row.project,
          workspace: row.workspace,
          terminalCount: state.tabsFor(row.workspace.id).length,
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
          onDelete: row.workspace.isMain
              ? null
              : () => onDeleteWorkspace(row.project, row.workspace),
        ),
      );
    }
    if (row is WorkbenchTerminalRow) {
      final leftPadding = row.indent <= 1
          ? AleraTokens.space20
          : AleraTokens.space32;
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, right: AleraTokens.space8),
        child: _TerminalRow(
          workspace: row.workspace,
          tab: row.tab,
          terminalRuntime: terminalRuntime,
          // A terminal only reads as "active" when both its workspace is the
          // currently selected workspace AND the tab is the active one for
          // that workspace. Otherwise an inactive workspace's last-active tab
          // would keep its highlight even though it is not really focused.
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
    final theme = Theme.of(context);
    final trimmed = query.trim();
    final message = trimmed.isEmpty
        ? 'No workspaces match the current filters'
        : 'No workspaces match "$trimmed"';
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundFaint,
          ),
        ),
      ),
    );
  }
}

class _ProjectHeaderTile extends StatefulWidget {
  const _ProjectHeaderTile({
    required this.project,
    required this.expanded,
    required this.workspaceCount,
    required this.onToggle,
    required this.onCreateWorkspace,
    required this.onRemoveProject,
  });

  final Project project;
  final bool expanded;
  final int workspaceCount;
  final VoidCallback onToggle;
  final VoidCallback onCreateWorkspace;
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
      items: const <PopupMenuEntry<String>>[
        DropdownEntry<String>(value: 'remove', label: 'Remove project'),
      ],
    );
    if (selected == 'remove') {
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
                const SizedBox(width: AleraTokens.space2),
                SidebarIconButton(
                  tooltip: 'New workspace in this project',
                  onPressed: widget.onCreateWorkspace,
                  icon: Icons.add,
                  iconSize: 14,
                  minSize: 24,
                ),
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
    required this.terminalCount,
    required this.isActive,
    required this.showProjectChip,
    required this.expanded,
    required this.onTap,
    required this.onOpenFolder,
    required this.onCopyPath,
    required this.onSleep,
    required this.onToggleExpanded,
    required this.fileManagerLabel,
    this.onDelete,
  });

  final Project project;
  final Workspace workspace;
  final int terminalCount;
  final bool isActive;
  final bool showProjectChip;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyPath;
  final VoidCallback onSleep;
  final VoidCallback onToggleExpanded;
  final String fileManagerLabel;
  final VoidCallback? onDelete;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
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
        _WorkspaceMenuEntry(
          value: _openFolderAction,
          icon: Icons.folder_open,
          label: 'Open in ${widget.fileManagerLabel}',
        ),
        const _WorkspaceMenuEntry(
          value: _copyPathAction,
          icon: Icons.copy,
          label: 'Copy path',
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const _WorkspaceMenuEntry(
          value: _sleepAction,
          icon: Icons.bedtime_outlined,
          label: 'Sleep workspace',
        ),
        _WorkspaceMenuEntry(
          value: _removeAction,
          icon: Icons.delete_outline,
          label: 'Remove workspace',
          enabled: widget.onDelete != null,
        ),
      ],
    );

    if (selected == _openFolderAction) {
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
    final parts = <String>[widget.workspace.branch];
    final source = widget.workspace.sourceBranch;
    if (!widget.workspace.isMain && source != null && source.isNotEmpty) {
      parts.add('base: $source');
    }
    if (widget.terminalCount > 0) {
      parts.add(
        widget.terminalCount == 1
            ? '1 terminal'
            : '${widget.terminalCount} terminals',
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
                      child: StatusDot(active: isActive),
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
                                const PrimaryBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: AleraTokens.space4),
                          Row(
                            children: <Widget>[
                              if (widget.showProjectChip) ...<Widget>[
                                Flexible(
                                  child: ProjectChip(
                                    label: widget.project.name,
                                  ),
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
                    SidebarIconButton(
                      tooltip: widget.expanded
                          ? 'Hide terminals'
                          : 'Show terminals',
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
                            child: SidebarIconButton(
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

class _WorkspaceMenuEntry extends PopupMenuEntry<String> {
  const _WorkspaceMenuEntry({
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final String value;
  final IconData icon;
  final String label;
  final bool enabled;

  @override
  double get height => 36;

  @override
  bool represents(String? value) => this.value == value;

  @override
  State<_WorkspaceMenuEntry> createState() => _WorkspaceMenuEntryState();
}

class _WorkspaceMenuEntryState extends State<_WorkspaceMenuEntry> {
  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        onTap: widget.enabled
            ? () => Navigator.of(context).pop(widget.value)
            : null,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              Icon(widget.icon, size: 16, color: color),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalRow extends StatefulWidget {
  const _TerminalRow({
    required this.workspace,
    required this.tab,
    required this.terminalRuntime,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final Workspace workspace;
  final TerminalTabRecord tab;
  final TerminalRuntime terminalRuntime;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TerminalRow> createState() => _TerminalRowState();
}

class _TerminalRowState extends State<_TerminalRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
    final session = widget.terminalRuntime.sessionFor(
      workspace: widget.workspace,
      tab: widget.tab,
    );
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
                vertical: AleraTokens.space4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.terminal,
                    size: 12,
                    color: isActive
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundFaint,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: session,
                      builder: (context, _) {
                        return Text(
                          session.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isActive
                                ? AleraTokens.foreground
                                : AleraTokens.foregroundMuted,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        );
                      },
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
                        child: InkWell(
                          onTap: widget.onClose,
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(
                            AleraTokens.radiusSm,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(AleraTokens.space2),
                            child: Tooltip(
                              message: 'Close terminal',
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: AleraTokens.foregroundMuted,
                              ),
                            ),
                          ),
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

class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView({required this.onAddProject});

  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Icon(
            Icons.folder_outlined,
            color: AleraTokens.foregroundFaint,
            size: 36,
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            'No projects yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            'Add a git repository to create workspaces and terminal tabs.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
          const SizedBox(height: AleraTokens.space16),
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add your first project'),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.onAddProject});

  final VoidCallback onAddProject;

  void _showPlaceholder(BuildContext context, String label) {
    AleraToast.show(
      context,
      message: '$label coming soon',
      tone: AleraToastTone.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.statusBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton.icon(
                onPressed: onAddProject,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Project'),
                style: TextButton.styleFrom(
                  foregroundColor: AleraTokens.foregroundMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space6,
                  ),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            const Spacer(),
            SidebarIconButton(
              tooltip: 'Settings',
              onPressed: () => _showPlaceholder(context, 'Settings'),
              icon: Icons.settings_outlined,
              iconSize: 14,
              minSize: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedSidebarFooter extends StatelessWidget {
  const _CollapsedSidebarFooter();

  void _showPlaceholder(BuildContext context, String label) {
    AleraToast.show(
      context,
      message: '$label coming soon',
      tone: AleraToastTone.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      child: SidebarIconButton(
        tooltip: 'Settings',
        onPressed: () => _showPlaceholder(context, 'Settings'),
        icon: Icons.settings_outlined,
        minSize: 28,
      ),
    );
  }
}
