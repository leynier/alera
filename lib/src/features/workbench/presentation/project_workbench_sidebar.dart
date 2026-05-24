import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_collapsed_rail.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_resize_handle.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_search_bar.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_section_header.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/presentation/dropdown_entry.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  onAddProject: _addProject,
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                SidebarSearchBar(
                  initialQuery: state.searchQuery,
                  focusNode: _searchFocus,
                  onChanged: controller.setSearchQuery,
                  hintText: 'Search workspaces',
                ),
                Expanded(
                  child: state.projects.isEmpty
                      ? _EmptyProjectsView(onAddProject: _addProject)
                      : _SidebarBody(
                          state: state,
                          controller: controller,
                          terminalRuntime: terminalRuntime,
                          onAddProject: _addProject,
                          onOpenWorkspace: _openWorkspace,
                          onCreateWorkspace: _createWorkspace,
                          onDeleteWorkspace: _deleteWorkspace,
                          onRemoveProject: _removeProject,
                          onSelectTerminal: _selectTerminal,
                          onCloseTerminal: _closeTerminal,
                        ),
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                const _SidebarFooter(),
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

  Future<void> _createWorkspace(Project project) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    List<String> branches;
    try {
      branches = await controller.listSourceBranches(project);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
      return;
    }
    if (!mounted) {
      return;
    }

    final result = await showDialog<CreateWorkspaceResult>(
      context: context,
      builder: (_) => CreateWorkspaceDialog(project: project, branches: branches),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await controller.createWorkspace(
        project: project,
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
      await ref.read(workbenchControllerProvider.notifier).deleteWorkspace(
        project: project,
        workspace: workspace,
      );
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
    final workspaces = ref.read(workbenchControllerProvider).workspacesFor(
      project.id,
    );
    for (final workspace in workspaces) {
      runtime.closeWorkspace(workspace.id);
    }
    try {
      await ref.read(workbenchControllerProvider.notifier).removeProject(
        project.id,
      );
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

  void _selectTerminal(Workspace workspace, String tabId) {
    ref
        .read(workbenchControllerProvider.notifier)
        .setActiveTab(workspaceId: workspace.id, tabId: tabId);
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
                chatCountByProject: workspaceCounts,
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
    required this.onAddProject,
    required this.onOpenWorkspace,
    required this.onCreateWorkspace,
    required this.onDeleteWorkspace,
    required this.onRemoveProject,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
  });

  final WorkbenchState state;
  final WorkbenchController controller;
  final TerminalRuntime terminalRuntime;
  final VoidCallback onAddProject;
  final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace;
  final Future<void> Function(Project project) onCreateWorkspace;
  final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace;
  final Future<void> Function(Project project) onRemoveProject;
  final _TerminalCallback onSelectTerminal;
  final _TerminalCallback onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    if (state.hasSearchQuery()) {
      return _SearchResults(
        state: state,
        onOpenWorkspace: onOpenWorkspace,
        onDeleteWorkspace: onDeleteWorkspace,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: AleraTokens.space4),
      children: <Widget>[
        for (final project in state.projects)
          _ProjectSection(
            project: project,
            state: state,
            controller: controller,
            terminalRuntime: terminalRuntime,
            onOpenWorkspace: onOpenWorkspace,
            onCreateWorkspace: onCreateWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            onRemoveProject: onRemoveProject,
            onSelectTerminal: onSelectTerminal,
            onCloseTerminal: onCloseTerminal,
          ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.state,
    required this.onOpenWorkspace,
    required this.onDeleteWorkspace,
  });

  final WorkbenchState state;
  final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace;
  final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = state.searchResults();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Center(
          child: Text(
            'No workspaces match "${state.searchQuery}"',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      children: <Widget>[
        for (final entry in results) ...<Widget>[
          SidebarSectionHeader(label: entry.project.name),
          for (final workspace in entry.workspaces)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
              child: _WorkspaceRow(
                workspace: workspace,
                terminalCount: state.tabsFor(workspace.id).length,
                isActive: workspace.id == state.activeWorkspaceId,
                onTap: () => onOpenWorkspace(entry.project, workspace),
                onDelete: workspace.isMain
                    ? null
                    : () => onDeleteWorkspace(entry.project, workspace),
              ),
            ),
          const SizedBox(height: AleraTokens.space4),
        ],
      ],
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.project,
    required this.state,
    required this.controller,
    required this.terminalRuntime,
    required this.onOpenWorkspace,
    required this.onCreateWorkspace,
    required this.onDeleteWorkspace,
    required this.onRemoveProject,
    required this.onSelectTerminal,
    required this.onCloseTerminal,
  });

  final Project project;
  final WorkbenchState state;
  final WorkbenchController controller;
  final TerminalRuntime terminalRuntime;
  final Future<void> Function(Project project, Workspace workspace)
  onOpenWorkspace;
  final Future<void> Function(Project project) onCreateWorkspace;
  final Future<void> Function(Project project, Workspace workspace)
  onDeleteWorkspace;
  final Future<void> Function(Project project) onRemoveProject;
  final _TerminalCallback onSelectTerminal;
  final _TerminalCallback onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    final expanded = state.expandedProjectIds.contains(project.id);
    final workspaces = state.workspacesFor(project.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space2,
          ),
          child: _WorkbenchProjectTile(
            project: project,
            expanded: expanded,
            workspaceCount: workspaces.length,
            onToggle: () => controller.toggleExpanded(project.id),
            onCreateWorkspace: () => onCreateWorkspace(project),
            onRemoveProject: () => onRemoveProject(project),
          ),
        ),
        if (expanded)
          if (workspaces.isEmpty)
            const Padding(
              padding: EdgeInsets.only(
                left: AleraTokens.space24,
                right: AleraTokens.space8,
                top: AleraTokens.space4,
                bottom: AleraTokens.space8,
              ),
              child: _LoadingWorkspaceHint(),
            )
          else
            Padding(
              padding: const EdgeInsets.only(
                left: AleraTokens.space20,
                right: AleraTokens.space8,
                bottom: AleraTokens.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final workspace in workspaces) ...<Widget>[
                    _WorkspaceRow(
                      workspace: workspace,
                      terminalCount: state.tabsFor(workspace.id).length,
                      isActive: workspace.id == state.activeWorkspaceId,
                      onTap: () => onOpenWorkspace(project, workspace),
                      onDelete: workspace.isMain
                          ? null
                          : () => onDeleteWorkspace(project, workspace),
                    ),
                    if (workspace.id == state.activeWorkspaceId &&
                        state.tabsFor(workspace.id).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AleraTokens.space20,
                          top: AleraTokens.space2,
                          bottom: AleraTokens.space2,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final tab in state.tabsFor(workspace.id))
                              _TerminalRow(
                                workspace: workspace,
                                tab: tab,
                                terminalRuntime: terminalRuntime,
                                isActive:
                                    state.activeTabIdByWorkspace[workspace.id] ==
                                        tab.id,
                                onTap: () => onSelectTerminal(workspace, tab.id),
                                onClose: () =>
                                    onCloseTerminal(workspace, tab.id),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

class _WorkbenchProjectTile extends StatefulWidget {
  const _WorkbenchProjectTile({
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
  State<_WorkbenchProjectTile> createState() => _WorkbenchProjectTileState();
}

class _WorkbenchProjectTileState extends State<_WorkbenchProjectTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onToggle,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          decoration: BoxDecoration(
            color: _hovered ? AleraTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                widget.expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space4),
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
              IgnorePointer(
                ignoring: !_hovered,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: AleraTokens.durationFast,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _ProjectActionButton(
                        tooltip: 'New workspace in this project',
                        icon: Icons.add,
                        onPressed: widget.onCreateWorkspace,
                      ),
                      _ProjectOptionsButton(
                        onRemoveProject: widget.onRemoveProject,
                      ),
                      const SizedBox(width: AleraTokens.space4),
                    ],
                  ),
                ),
              ),
              Text(
                widget.workspaceCount.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectActionButton extends StatelessWidget {
  const _ProjectActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 14, color: AleraTokens.foregroundMuted),
        ),
      ),
    );
  }
}

class _ProjectOptionsButton extends StatelessWidget {
  const _ProjectOptionsButton({required this.onRemoveProject});

  final VoidCallback onRemoveProject;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Project options',
      child: InkWell(
        onTap: () async {
          final button = context.findRenderObject()! as RenderBox;
          final overlay =
              Navigator.of(context).overlay!.context.findRenderObject()!
                  as RenderBox;
          final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
          final bottomRight = button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          );
          final selected = await showMenu<String>(
            context: context,
            position: RelativeRect.fromRect(
              Rect.fromPoints(topLeft, bottomRight),
              Offset.zero & overlay.size,
            ),
            items: const <PopupMenuEntry<String>>[
              DropdownEntry<String>(value: 'remove', label: 'Remove project'),
            ],
          );
          if (selected == 'remove') {
            onRemoveProject();
          }
        },
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: const SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            Icons.more_horiz,
            size: 14,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow({
    required this.workspace,
    required this.terminalCount,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  final Workspace workspace;
  final int terminalCount;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  bool _hovered = false;

  String _buildSecondaryLine() {
    final parts = <String>[widget.workspace.branch];
    final source = widget.workspace.sourceBranch;
    if (!widget.workspace.isMain && source != null && source.isNotEmpty) {
      parts.add('base: $source');
    }
    if (widget.terminalCount > 0) {
      parts.add(
        widget.terminalCount == 1 ? '1 terminal' : '${widget.terminalCount} terminals',
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
        child: Stack(
          children: <Widget>[
            AnimatedContainer(
              duration: AleraTokens.durationMid,
              decoration: BoxDecoration(
                color: isActive
                    ? AleraTokens.surfaceElevated
                    : (_hovered ? AleraTokens.surface : Colors.transparent),
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              ),
              child: InkWell(
                onTap: widget.onTap,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                    vertical: AleraTokens.space6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        widget.workspace.isMain
                            ? Icons.home_work_outlined
                            : Icons.account_tree_outlined,
                        size: 14,
                        color: isActive
                            ? AleraTokens.foreground
                            : AleraTokens.foregroundFaint,
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
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isActive
                                          ? AleraTokens.foreground
                                          : AleraTokens.foregroundMuted,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AleraTokens.space6),
                                _MiniBadge(
                                  label: widget.workspace.isMain
                                      ? 'Main'
                                      : 'Linked',
                                ),
                              ],
                            ),
                            const SizedBox(height: AleraTokens.space2),
                            Text(
                              _buildSecondaryLine(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AleraTokens.foregroundFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onDelete != null)
                        IgnorePointer(
                          ignoring: !actionsVisible,
                          child: AnimatedOpacity(
                            opacity: actionsVisible ? 1 : 0,
                            duration: AleraTokens.durationFast,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: AleraTokens.space4,
                              ),
                              child: IconButton(
                                tooltip: 'Remove workspace',
                                onPressed: widget.onDelete,
                                icon: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AleraTokens.foregroundMuted,
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 22,
                                  minHeight: 22,
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
            if (isActive)
              Positioned(
                left: 0,
                top: AleraTokens.space4,
                bottom: AleraTokens.space4,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: AleraTokens.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
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

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}

class _LoadingWorkspaceHint extends StatelessWidget {
  const _LoadingWorkspaceHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Preparing the main workspace…',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AleraTokens.foregroundFaint,
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
  const _SidebarFooter();

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
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: () => _showPlaceholder(context, 'Settings'),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Settings'),
              style: TextButton.styleFrom(
                foregroundColor: AleraTokens.foregroundMuted,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                ),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Help',
              onPressed: () => _showPlaceholder(context, 'Help'),
              icon: const Icon(Icons.help_outline, size: 16),
              style: IconButton.styleFrom(
                foregroundColor: AleraTokens.foregroundMuted,
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(28),
                maximumSize: const Size.square(28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                ),
              ),
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
      padding: const EdgeInsets.symmetric(
        vertical: AleraTokens.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _showPlaceholder(context, 'Settings'),
            icon: const Icon(Icons.settings_outlined, size: 16),
            style: IconButton.styleFrom(
              foregroundColor: AleraTokens.foregroundMuted,
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(28),
              maximumSize: const Size.square(28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              ),
            ),
          ),
          const SizedBox(height: AleraTokens.space2),
          IconButton(
            tooltip: 'Help',
            onPressed: () => _showPlaceholder(context, 'Help'),
            icon: const Icon(Icons.help_outline, size: 16),
            style: IconButton.styleFrom(
              foregroundColor: AleraTokens.foregroundMuted,
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(28),
              maximumSize: const Size.square(28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
