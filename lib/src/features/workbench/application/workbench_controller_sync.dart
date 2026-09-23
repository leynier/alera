part of 'workbench_controller.dart';

mixin _WorkbenchControllerSync
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspaceReconciliation,
        _WorkbenchControllerTransfer,
        _WorkbenchControllerInternalLayout {
  void _enqueueWorkspaceSync(Future<void> Function() update) {
    if (_transferringWorkspace) {
      _refreshAfterTransfer = true;
      return;
    }
    _workspaceSyncQueue = _workspaceSyncQueue
        .then((_) async {
          if (_disposed) return;
          if (_transferringWorkspace) {
            _refreshAfterTransfer = true;
            return;
          }
          await update();
        })
        .catchError((Object error) {
          if (!_disposed) {
            state = state.copyWith(
              error: 'Could not reconcile workspace state: $error',
            );
          }
        });
  }

  Future<void> _reconcileMigratedTabs(String workspaceId) async {
    final selectionRevision = _workspaceSelectionRevision;
    final source = _workspaceById(workspaceId);
    if (source == null) return;
    final destinations = <String, Set<String>>{};
    for (final tab in state.tabsFor(workspaceId)) {
      final live = await _repository.findWorkspaceTabById(tab.id);
      if (live != null && live.workspaceId != workspaceId) {
        destinations
            .putIfAbsent(live.workspaceId, () => <String>{})
            .add(tab.id);
      }
    }
    for (final entry in destinations.entries) {
      final destination = await _repository.findWorkspaceById(entry.key);
      if (destination == null || _disposed) continue;
      final wasActive = state.activeWorkspaceId == source.id;
      _transferWorkspaceContents(source, destination, tabIds: entry.value);
      final layout = await _repository.findWorkbenchLayout(destination.id);
      if (layout != null) await _applyLayout(layout, persist: false);
      final project = state.projects
          .where((entry) => entry.id == destination.projectId)
          .firstOrNull;
      if (project != null) {
        _reconcileCreatedWorkspace(project, destination);
        if (wasActive &&
            selectionRevision == _workspaceSelectionRevision &&
            state.activeWorkspaceId == source.id) {
          state = state.copyWith(activeWorkspaceId: destination.id);
        }
      }
    }
  }

  @override
  Future<void> _refreshProjectAfterTransfer(Project project) async {
    for (final workspace in state.workspacesFor(project.id).toList()) {
      await _reconcileMigratedTabs(workspace.id);
    }
    final workspaces = await _repository.listWorkspaces(project.id);
    if (_disposed) return;
    _applyWorkspacesChanged(project, workspaces);
    for (final workspace in workspaces) {
      final tabs = await _repository.listWorkspaceTabs(workspace.id);
      final layout = await _repository.findWorkbenchLayout(workspace.id);
      if (_disposed) return;
      if (layout != null) await _applyLayout(layout, persist: false);
      _applyTabsChanged(workspace.id, tabs);
    }
  }

  /// Frees the live terminal handles and editor documents of a workspace that
  /// no longer exists in persisted state.
  ///
  /// The managed runtime stops PTYs before publishing removal. Releasing local
  /// handles also covers changes from another client without sending a second
  /// termination request for sessions this client no longer owns.
  void _releaseRetiredWorkspaceSessions(String workspaceId) {
    _tabFocusHistory.forget(workspaceId);
    _panelSelectionRevisionByWorkspace.remove(workspaceId);
    ref.read(terminalRuntimeProvider).releaseWorkspace(workspaceId);
    final editorSessions = ref.read(editorSessionRegistryProvider);
    for (final tab in state.tabsFor(workspaceId)) {
      editorSessions.forget(tab.id);
      if (tab.kind == WorkspaceTabKind.terminal &&
          ref.exists(agentHookReceiverProvider)) {
        ref
            .read(agentHookReceiverProvider)
            .clearTerminalSession(tab.terminalSessionId);
      }
    }
  }

  void _onProjectsChanged(List<Project> projects) {
    final validProjectIds = <String>{
      for (final project in projects) project.id,
    };
    // Prune collapse/selection ids that point at removed projects. New
    // projects are not added to either set so they show up expanded and (when
    // there is no active selection) visible by default.
    final prefs = state.viewPrefs;
    final prunedCollapsed = prefs.collapsedProjectIds
        .where(validProjectIds.contains)
        .toSet();
    final prunedSelected = prefs.selectedProjectIds
        .where(validProjectIds.contains)
        .toSet();
    final removedProjectWorkspaceIds = <String>{
      for (final entry in state.workspacesByProject.entries)
        if (!validProjectIds.contains(entry.key))
          for (final workspace in entry.value) workspace.id,
    };
    for (final entry in state.workspacesByProject.entries) {
      if (validProjectIds.contains(entry.key)) {
        continue;
      }
      for (final workspace in entry.value) {
        _releaseHostedReviewTabsInBackground(
          workspace,
          state.tabsFor(workspace.id),
        );
        _releaseRetiredWorkspaceSessions(workspace.id);
      }
    }
    final prunedSourceControlRoots =
        Map<String, String>.from(prefs.sourceControlRootByWorkspaceId)
          ..removeWhere(
            (workspaceId, _) =>
                removedProjectWorkspaceIds.contains(workspaceId),
          );
    final prunedRightSidebarWidths =
        Map<String, double>.from(prefs.rightSidebarWidthByWorkspaceId)
          ..removeWhere(
            (workspaceId, _) =>
                removedProjectWorkspaceIds.contains(workspaceId),
          );
    final prunedWorkspacePanels =
        Map<String, WorkspacePanel>.from(prefs.workspacePanels)..removeWhere(
          (workspaceId, _) => removedProjectWorkspaceIds.contains(workspaceId),
        );
    final prefsChanged =
        prunedCollapsed.length != prefs.collapsedProjectIds.length ||
        prunedSelected.length != prefs.selectedProjectIds.length ||
        prunedSourceControlRoots.length !=
            prefs.sourceControlRootByWorkspaceId.length ||
        prunedRightSidebarWidths.length !=
            prefs.rightSidebarWidthByWorkspaceId.length ||
        prunedWorkspacePanels.length != prefs.workspacePanels.length;
    final prunedViewPrefs = prefsChanged
        ? prefs.copyWith(
            collapsedProjectIds: prunedCollapsed,
            selectedProjectIds: prunedSelected,
            sourceControlRootByWorkspaceId: prunedSourceControlRoots,
            rightSidebarWidthByWorkspaceId: prunedRightSidebarWidths,
            workspacePanels: prunedWorkspacePanels,
          )
        : prefs;
    final updatedWorkspaces = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        if (validProjectIds.contains(entry.key)) entry.key: entry.value,
    };
    final liveWorkspaceIds = <String>{
      for (final workspaces in updatedWorkspaces.values)
        for (final workspace in workspaces) workspace.id,
    };
    final updatedTabs = <String, List<WorkspaceTabRecord>>{
      for (final entry in state.tabsByWorkspace.entries)
        if (liveWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final updatedLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (liveWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final updatedActiveTabs = <String, String>{
      for (final entry in state.activeTabIdByWorkspace.entries)
        if (liveWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };

    final currentActiveProjectId =
        state.activeProjectId != null &&
            validProjectIds.contains(state.activeProjectId)
        ? state.activeProjectId
        : (projects.isNotEmpty ? projects.first.id : null);
    final activeProjectId = currentActiveProjectId;
    final activeWorkspaceId = _resolveActiveWorkspaceId(
      activeProjectId: activeProjectId,
      workspacesByProject: updatedWorkspaces,
      preferredWorkspaceId: state.activeWorkspaceId,
    );
    final nextViewPrefs = prunedViewPrefs;
    final viewPrefsChanged = prefsChanged;

    state = state.copyWith(
      projects: projects,
      workspacesByProject: updatedWorkspaces,
      tabsByWorkspace: updatedTabs,
      viewPrefs: nextViewPrefs,
      activeProjectId: activeProjectId,
      activeWorkspaceId: activeWorkspaceId,
      activeTabIdByWorkspace: updatedActiveTabs,
      layoutByWorkspace: updatedLayouts,
    );
    _pruneWorktreeNavigationHistory();
    if (viewPrefsChanged) {
      unawaited(_persistViewPrefs());
    }
    _pruneExplorerSessions();

    for (final project in projects) {
      if (_workspaceSubs.containsKey(project.id)) {
        continue;
      }
      _workspaceSubs[project.id] = _repository
          .watchWorkspaces(project.id)
          .listen(
            (workspaces) => _onWorkspacesChanged(project, workspaces),
            // Re-subscription is guarded by `containsKey`, so a subscription
            // that dies must drop out of the map or the project stops syncing
            // for the rest of the session.
            onError: (Object _) {},
            onDone: () => _workspaceSubs.remove(project.id),
            cancelOnError: false,
          );
      unawaited(_reconcileProjectWorkspaces(project));
    }

    final removedProjectIds = _workspaceSubs.keys
        .where((projectId) => !validProjectIds.contains(projectId))
        .toList(growable: false);
    for (final projectId in removedProjectIds) {
      _workspaceSubs.remove(projectId)?.cancel();
      final removedWorkspaceIds = _tabSubProjectIds.entries
          .where((entry) => entry.value == projectId)
          .map((entry) => entry.key)
          .toList(growable: false);
      for (final workspaceId in removedWorkspaceIds) {
        _tabSubs.remove(workspaceId)?.cancel();
        _tabSubProjectIds.remove(workspaceId);
      }
      _workspaceIdsWithClearedLayout.removeAll(removedWorkspaceIds);
    }
    _ensureSelectionHasTab();
  }
}
