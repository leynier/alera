part of 'project_workbench_sidebar.dart';

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

  Future<void> _setWorkspacePinned(Workspace workspace, bool isPinned) async {
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .setWorkspacePinned(workspaceId: workspace.id, isPinned: isPinned);
      if (!mounted) return;
      AleraToast.show(
        context,
        message: isPinned ? 'Workspace pinned' : 'Workspace unpinned',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) return;
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
          tone: AleraToastTone.error,
        );
        return;
      }
    }
    final shouldConfirm =
        impact != null ||
        ref.read(settingsControllerProvider).general.confirmWorkspaceRemoval;
    final lastActivity =
        ref.read(workspaceActivityControllerProvider)[workspace.id] ??
        impact?.lastActivityAt ??
        workspace.updatedAt;
    final impactSummary = impact == null
        ? ''
        : 'Measured size: ${formatResourceMemory(impact.sizeBytes)} '
              'across ${impact.entryCount} entries.\n'
              'Last activity: ${_workspaceStorageTimestamp(lastActivity)}.\n\n';
    final confirmed = shouldConfirm
        ? await showDialog<bool>(
            context: context,
            builder: (_) => AleraConfirmDialog(
              title: impact == null
                  ? 'Remove Workspace?'
                  : 'Clean Up Workspace?',
              message:
                  '$impactSummary${!deleteBranch || branch == null || branch.isEmpty ? 'This removes the worktree for "${workspace.name}".' : 'This removes the worktree for "${workspace.name}" and deletes branch "$branch".'}',
              confirmLabel: impact == null ? 'Remove' : 'Clean Up',
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
          .deleteWorkspace(
            project: project,
            workspace: workspace,
            deleteBranch: deleteBranch,
            activeWorkspaceId: ref
                .read(workbenchControllerProvider)
                .activeWorkspaceId,
          );
      await ref
          .read(browserSessionRegistryProvider)
          .closeWorkspace(workspace.id);
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

  String _workspaceStorageTimestamp(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<void> _manageWorkspaceTags(Workspace workspace) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      final tags = await controller.listWorkspaceTags();
      if (!mounted) {
        return;
      }
      final selection = await showWorkspaceTagsDialog(
        context: context,
        workspace: workspace,
        tags: tags,
        onCreateTag: controller.createWorkspaceTag,
        onDeleteTag: controller.deleteWorkspaceTag,
      );
      if (selection == null || !mounted) {
        return;
      }
      await controller.updateWorkspaceTags(
        workspace: workspace,
        tagIds: selection.tagIds,
      );
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Workspace tags updated',
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

  Future<void> _setWorkspaceParent(Workspace workspace) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      final relations = await controller.listWorkspaceRelations();
      if (!mounted) {
        return;
      }
      final selection = await showWorkspaceParentDialog(
        context: context,
        workspace: workspace,
        options: _workspaceParentOptions(),
        relations: relations,
      );
      if (selection == null || !mounted) {
        return;
      }
      await controller.setWorkspaceParent(
        workspace: workspace,
        parentWorkspaceId: selection.parentWorkspaceId,
      );
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Workspace parent updated',
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

  Future<void> _clearWorkspaceParent(Workspace workspace) async {
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .setWorkspaceParent(workspace: workspace);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Workspace parent cleared',
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
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .removeProject(project.id);
      for (final workspace in workspaces) {
        await ref
            .read(browserSessionRegistryProvider)
            .closeWorkspace(workspace.id);
      }
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
    if (tabRecord.kind == WorkspaceTabKind.codex) {
      return;
    }
    ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: workspace, tab: tabRecord)
        .requestFocus();
  }

  Future<void> _closeTerminal(Workspace workspace, String tabId) async {
    final tab = ref
        .read(workbenchControllerProvider)
        .tabsFor(workspace.id)
        .where((candidate) => candidate.id == tabId)
        .firstOrNull;
    if (tab?.kind != WorkspaceTabKind.codex) {
      ref.read(terminalRuntimeProvider).closeTab(tabId);
    }
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
