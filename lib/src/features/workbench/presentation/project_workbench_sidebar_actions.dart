part of 'project_workbench_sidebar.dart';

enum _WorkbenchSidebarMutation(final String successMessage) {
  renameProject('Project renamed'),
  renameWorkspace('Workspace renamed'),
  pinWorkspace('Workspace pinned'),
  unpinWorkspace('Workspace unpinned'),
  pinWorkspaceTree('Workspace tree pinned'),
  unpinWorkspaceTree('Workspace tree unpinned'),
  removeWorkspace('Workspace removed'),
  updateWorkspaceTags('Workspace tags updated'),
  updateWorkspaceParent('Workspace parent updated'),
  clearWorkspaceParent('Workspace parent cleared'),
  removeProject('Project removed'),
}

enum _WorkbenchSidebarMutationResult { applied, notApplied }

mixin _ProjectWorkbenchSidebarActions
    on ConsumerState<ProjectWorkbenchSidebar>, _WorkspaceSidebarActions {
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

  Future<void> _openAutomations() => openAutomationsDialog(context);

  Future<void> _openProjectSettings(Project project) => openSettingsDialog(
    context,
    initialSectionId: 'projects',
    initialProjectId: project.id,
  );

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
    await _runWorkbenchSidebarMutation(
      mutation: .renameProject,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .renameProject(projectId: project.id, name: name);
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
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
    await _runWorkbenchSidebarMutation(
      mutation: .renameWorkspace,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .renameWorkspace(workspaceId: workspace.id, name: name);
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  Future<void> _setWorkspacePinned(Workspace workspace, bool isPinned) async {
    await _runWorkbenchSidebarMutation(
      mutation: isPinned
          ? _WorkbenchSidebarMutation.pinWorkspace
          : _WorkbenchSidebarMutation.unpinWorkspace,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .setWorkspacePinned(workspaceId: workspace.id, isPinned: isPinned);
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  Future<void> _setWorkspaceTreePinned(
    Workspace workspace,
    bool isPinned,
  ) async {
    await _runWorkbenchSidebarMutation(
      mutation: isPinned
          ? _WorkbenchSidebarMutation.pinWorkspaceTree
          : _WorkbenchSidebarMutation.unpinWorkspaceTree,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .setWorkspaceTreePinned(
              workspaceId: workspace.id,
              isPinned: isPinned,
            );
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  Future<void> _deleteWorkspace(Project project, Workspace workspace) async {
    if (workspace.isMain) {
      return;
    }
    final branch = workspace.branch;
    final deleteBranch = !workspace.reusesExistingBranch;
    final managedRuntime = ref.read(managedWorkspaceRuntimeProvider);
    WorkspaceStorageImpact? impact;
    if (managedRuntime is WorkspaceStorageRuntime) {
      try {
        final measuredImpact = await (managedRuntime as WorkspaceStorageRuntime)
            .storageImpact(
              workspaceId: workspace.id,
              activeWorkspaceId: ref
                  .read(workbenchControllerProvider)
                  .activeWorkspaceId,
            );
        impact = measuredImpact;
        if (!mounted) return;
        if (!measuredImpact.safeToClean) {
          await showDialog<bool>(
            context: context,
            builder: (_) => AleraConfirmDialog(
              title: 'Cleanup Unavailable',
              message:
                  'Alera measured ${formatResourceMemory(measuredImpact.sizeBytes)} across '
                  '${measuredImpact.entryCount} entries. Cleanup is blocked:\n\n'
                  '${measuredImpact.blockers.map((blocker) => '• $blocker').join('\n')}',
              confirmLabel: 'Close',
              cancelLabel: 'Cancel',
            ),
          );
          return;
        }
      } catch (error) {
        if (!mounted) return;
        AleraToast.show(
          context,
          message: 'Could not inspect workspace storage: $error',
          tone: .error,
        );
        return;
      }
    }
    final lastActivity =
        ref.read(workspaceActivityControllerProvider)[workspace.id] ??
        impact?.lastActivityAt ??
        workspace.updatedAt;
    final impactSummary = impact == null
        ? ''
        : 'Measured size: ${formatResourceMemory(impact.sizeBytes)} '
              'across ${impact.entryCount} entries.\n'
              'Last activity: ${_workspaceStorageTimestamp(lastActivity)}.\n\n';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: impact == null ? 'Remove Workspace?' : 'Clean Up Workspace?',
        message:
            '$impactSummary${!deleteBranch || branch == null || branch.isEmpty ? 'This removes the worktree for "${workspace.name}".' : 'This removes the worktree for "${workspace.name}" and deletes branch "$branch".'}'
            '\n\nAll tabs will close and running terminals, agents, and their child processes will stop. Unsaved changes will be lost. If removal fails, stopped sessions will not restart automatically.',
        confirmLabel: impact == null ? 'Remove' : 'Clean Up',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runWorkbenchSidebarMutation(
      mutation: .removeWorkspace,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .deleteWorkspace(
              project: project,
              workspace: workspace,
              deleteBranch: deleteBranch,
              activeWorkspaceId: ref
                  .read(workbenchControllerProvider)
                  .activeWorkspaceId,
            );
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  String _workspaceStorageTimestamp(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<void> _manageWorkspaceTags(Workspace workspace) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    return _runWorkbenchSidebarMutation(
      mutation: .updateWorkspaceTags,
      execute: () async {
        final tags = await controller.listWorkspaceTags();
        if (!mounted) {
          return _WorkbenchSidebarMutationResult.notApplied;
        }
        final selection = await showWorkspaceTagsDialog(
          context: context,
          workspace: workspace,
          tags: tags,
          onCreateTag: controller.createWorkspaceTag,
          onDeleteTag: controller.deleteWorkspaceTag,
        );
        if (selection == null || !mounted) {
          return _WorkbenchSidebarMutationResult.notApplied;
        }
        await controller.updateWorkspaceTags(
          workspace: workspace,
          tagIds: selection.tagIds,
        );
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  Future<void> _setWorkspaceParent(Workspace workspace) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    return _runWorkbenchSidebarMutation(
      mutation: .updateWorkspaceParent,
      execute: () async {
        final relations = await controller.listWorkspaceRelations();
        if (!mounted) {
          return _WorkbenchSidebarMutationResult.notApplied;
        }
        final selection = await showWorkspaceParentDialog(
          context: context,
          workspace: workspace,
          options: _workspaceParentOptions(),
          relations: relations,
        );
        if (selection == null || !mounted) {
          return _WorkbenchSidebarMutationResult.notApplied;
        }
        await controller.setWorkspaceParent(
          workspace: workspace,
          parentWorkspaceId: selection.parentWorkspaceId,
        );
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  Future<void> _clearWorkspaceParent(Workspace workspace) {
    return _runWorkbenchSidebarMutation(
      mutation: .clearWorkspaceParent,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .setWorkspaceParent(workspace: workspace);
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  List<WorkspaceParentOption> _workspaceParentOptions() {
    final state = ref.read(workbenchControllerProvider);
    return <WorkspaceParentOption>[
      for (final project in state.projects)
        for (final workspace in state.workspacesFor(project.id))
          if (workspace.isActive)
            WorkspaceParentOption(project: project, workspace: workspace),
    ];
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
    await _runWorkbenchSidebarMutation(
      mutation: .removeProject,
      execute: () async {
        await ref
            .read(workbenchControllerProvider.notifier)
            .removeProject(project.id);
        return _WorkbenchSidebarMutationResult.applied;
      },
    );
  }

  Future<void> _runWorkbenchSidebarMutation({
    required _WorkbenchSidebarMutation mutation,
    required Future<_WorkbenchSidebarMutationResult> Function() execute,
  }) async {
    try {
      final result = await execute();
      if (result != _WorkbenchSidebarMutationResult.applied || !mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: mutation.successMessage,
        tone: .success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: error.toString(), tone: .error);
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
    if (tabRecord.kind == WorkspaceTabKind.codex) {
      return;
    }
    ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: workspace, tab: tabRecord)
        .requestFocus();
  }

  Future<void> _closeTerminal(Workspace workspace, String tabId) async {
    try {
      final tab = ref
          .read(workbenchControllerProvider)
          .tabsFor(workspace.id)
          .where((tab) => tab.id == tabId)
          .firstOrNull;
      if (tab?.kind == WorkspaceTabKind.codex &&
          !await confirmCodexQueueClose(context, ref, tabId)) {
        return;
      }
      // The controller disposes the terminal handle alongside the tab record.
      await ref
          .read(workbenchControllerProvider.notifier)
          .closeWorkspaceTab(workspace: workspace, tabId: tabId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: error.toString(), tone: .error);
    }
  }
}
