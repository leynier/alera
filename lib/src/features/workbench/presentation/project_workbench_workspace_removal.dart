part of 'project_workbench_sidebar.dart';

extension _ProjectWorkbenchWorkspaceRemoval on _ProjectWorkbenchSidebarActions {
  Future<void> _deleteWorkspace(Project project, Workspace workspace) async {
    final branch = workspace.branch;
    final canDeleteBranch =
        !workspace.isMain &&
        !workspace.reusesExistingBranch &&
        branch != null &&
        branch.isNotEmpty;

    final managedRuntime = ref.read(managedWorkspaceRuntimeProvider);
    final dependencyRuntime =
        managedRuntime is WorkspaceRemovalDependencyRuntime
        ? managedRuntime as WorkspaceRemovalDependencyRuntime
        : null;
    List<WorkspaceRemovalDependency> dependencies;
    try {
      dependencies =
          await dependencyRuntime?.removalDependencies(workspace.id) ??
          const [];
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: 'Could not verify automation dependencies: $error',
          tone: .error,
        );
      }
      return;
    }
    if (!mounted) return;
    WorkspaceStorageImpact? impact;
    if (!workspace.isMain && managedRuntime is WorkspaceStorageRuntime) {
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
        final blockers = measuredImpact.blockers
            .where(
              (blocker) =>
                  !(blocker == 'Workspace is owned by an active automation' &&
                      dependencies.any(
                        (dependency) => dependency.requiresPause,
                      )),
            )
            .toList();
        if (!measuredImpact.safeToClean && blockers.isNotEmpty) {
          await showDialog<bool>(
            context: context,
            builder: (_) => AleraConfirmDialog(
              title: 'Cleanup Unavailable',
              message:
                  'Alera measured ${formatResourceMemory(measuredImpact.sizeBytes)} across '
                  '${measuredImpact.entryCount} entries. Cleanup is blocked:\n\n'
                  '${blockers.map((blocker) => '• $blocker').join('\n')}',
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
    final decision = await showWorkspaceRemovalDialog(
      context,
      workspaceName: workspace.name,
      branch: branch,
      canDeleteBranch: canDeleteBranch,
      sharedCheckout: workspace.isMain,
      impactSummary: impactSummary,
    );
    if (decision == null || !mounted) {
      return;
    }
    final registry = ref.read(editorSessionRegistryProvider);
    final tabsToDiscard = <String>[];
    final dirtyTabs = ref
        .read(workbenchControllerProvider)
        .tabsFor(workspace.id)
        .where((tab) => registry.isDirty(tab.id))
        .toList();
    if (dirtyTabs.isNotEmpty) {
      final save = await showWorkspaceUnsavedChangesDialog(
        context,
        dirtyTabs.map((tab) => tab.title).toList(),
      );
      if (save == null || !mounted) return;
      if (save) {
        try {
          final files = ref.read(workspaceFileServiceProvider);
          for (final tab in dirtyTabs) {
            await registry.saveDocument(tab.id, files);
          }
          if (dirtyTabs.any((tab) => registry.isDirty(tab.id))) {
            throw StateError('Some documents still have unsaved changes.');
          }
        } catch (error) {
          if (mounted) {
            AleraToast.show(context, message: error.toString(), tone: .error);
          }
          return;
        }
      } else {
        tabsToDiscard.addAll(dirtyTabs.map((tab) => tab.id));
      }
    }
    if (!mounted) return;
    if (dependencies.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: 'Dependent Automations',
          message:
              '${dependencies.map((dependency) => '${dependency.name}: ${dependency.activeRuns} active runs').join('\n')}\n\nContinuing pauses these automations when needed and cancels all of their active runs. Their history is preserved. Targets referring to this workspace will need to be changed before resuming.',
          confirmLabel: 'Pause And Continue',
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _runWorkbenchSidebarMutation(
      mutation: .removeWorkspace,
      execute: () async {
        if (dependencyRuntime != null && dependencies.isNotEmpty) {
          await dependencyRuntime.pauseRemovalDependencies(
            workspace.id,
            dependencies,
          );
        }
        for (final tabId in tabsToDiscard) {
          await registry.discard(tabId);
        }
        await ref
            .read(workbenchControllerProvider.notifier)
            .deleteWorkspace(
              project: project,
              workspace: workspace,
              deleteBranch: decision.deleteBranch,
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
}
