import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
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

part 'project_workbench_collapsed_sidebar.dart';
part 'project_workbench_sidebar_body.dart';
part 'project_workbench_workspace_rows.dart';
part 'project_workbench_agent_rows.dart';
part 'project_workbench_sidebar_footer.dart';

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
      message: 'Workspace Slept',
      tone: AleraToastTone.success,
    );
  }

  Future<void> _renameProject(Project project) async {
    final name = await showRenameDialog(
      context,
      title: 'Rename Project',
      labelText: 'Project Name',
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
        message: 'Project Renamed',
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
      title: 'Rename Workspace',
      labelText: 'Workspace Name',
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
        message: 'Workspace Renamed',
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
              title: 'Remove Workspace?',
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
        message: 'Workspace Removed',
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
              title: 'Remove Project?',
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
        message: 'Project Removed',
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
