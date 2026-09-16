part of 'workbench_controller.dart';

mixin _WorkbenchControllerSync
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspaceReconciliation,
        _WorkbenchControllerTransfer {
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

  void _onWorkspacesChanged(Project project, List<Workspace> workspaces) {
    _enqueueWorkspaceSync(() async {
      final ids = workspaces.map((workspace) => workspace.id).toSet();
      if (state
          .workspacesFor(project.id)
          .any((workspace) => !ids.contains(workspace.id))) {
        await _refreshProjectAfterTransfer(project);
      } else {
        _applyWorkspacesChanged(project, workspaces);
      }
    });
  }

  void _applyWorkspacesChanged(Project project, List<Workspace> workspaces) {
    final nextWorkspaces = Map<String, List<Workspace>>.from(
      state.workspacesByProject,
    )..[project.id] = workspaces;
    final liveWorkspaceIds = <String>{
      for (final workspace in workspaces) workspace.id,
    };
    final removedWorkspaceIds = _tabSubProjectIds.entries
        .where(
          (entry) =>
              entry.value == project.id &&
              !liveWorkspaceIds.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final workspaceId in removedWorkspaceIds) {
      final workspace = _workspaceById(workspaceId);
      if (workspace != null) {
        _releaseHostedReviewTabsInBackground(
          workspace,
          state.tabsFor(workspaceId),
        );
      }
      _releaseRetiredWorkspaceSessions(workspaceId);
    }
    for (final workspaceId in removedWorkspaceIds) {
      _tabSubs.remove(workspaceId)?.cancel();
      _tabSubProjectIds.remove(workspaceId);
    }
    _workspaceIdsWithClearedLayout.removeAll(removedWorkspaceIds);
    final nextLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    for (final workspace in workspaces) {
      if (_tabSubs.containsKey(workspace.id)) {
        continue;
      }
      _tabSubProjectIds[workspace.id] = project.id;
      unawaited(_loadLayoutForWorkspace(workspace.id));
      _tabSubs[workspace.id] = _repository
          .watchWorkspaceTabs(workspace.id)
          .listen(
            (tabs) => _onTabsChanged(workspace.id, tabs),
            onError: (Object _) {},
            onDone: () {
              _tabSubs.remove(workspace.id);
              _tabSubProjectIds.remove(workspace.id);
            },
            cancelOnError: false,
          );
    }
    // Preserve the active project while it is still valid; never silently jump
    // to a different project just because this project's workspaces changed.
    final candidateProjectId =
        (state.activeProjectId != null &&
            state.projects.any((proj) => proj.id == state.activeProjectId))
        ? state.activeProjectId
        : project.id;
    final activeWorkspaceId = _resolveActiveWorkspaceId(
      activeProjectId: candidateProjectId,
      workspacesByProject: nextWorkspaces,
      preferredWorkspaceId: state.activeWorkspaceId,
    );
    // Drop any expansion entries that pointed at workspaces that no longer
    // exist so the set stays tight.
    final viewPrefs = state.viewPrefs;
    final prunedExpanded = viewPrefs.expandedWorkspaceIds
        .where(
          (id) =>
              !removedWorkspaceIds.contains(id) ||
              liveWorkspaceIds.contains(id),
        )
        .toSet();
    final expansionChanged =
        prunedExpanded.length != viewPrefs.expandedWorkspaceIds.length;
    final expandedViewPrefs = expansionChanged
        ? viewPrefs.copyWith(expandedWorkspaceIds: prunedExpanded)
        : viewPrefs;
    final prunedSourceControlRoots =
        Map<String, String>.from(
          expandedViewPrefs.sourceControlRootByWorkspaceId,
        )..removeWhere(
          (workspaceId, _) => removedWorkspaceIds.contains(workspaceId),
        );
    final prunedRightSidebarWidths =
        Map<String, double>.from(
          expandedViewPrefs.rightSidebarWidthByWorkspaceId,
        )..removeWhere(
          (workspaceId, _) => removedWorkspaceIds.contains(workspaceId),
        );
    final prunedWorkspacePanels =
        Map<String, WorkspacePanel>.from(expandedViewPrefs.workspacePanels)
          ..removeWhere(
            (workspaceId, _) => removedWorkspaceIds.contains(workspaceId),
          );
    final sourceControlRootsChanged =
        prunedSourceControlRoots.length !=
        expandedViewPrefs.sourceControlRootByWorkspaceId.length;
    final rightSidebarWidthsChanged =
        prunedRightSidebarWidths.length !=
        expandedViewPrefs.rightSidebarWidthByWorkspaceId.length;
    final workspacePanelsChanged =
        prunedWorkspacePanels.length !=
        expandedViewPrefs.workspacePanels.length;
    var workspacePrunedViewPrefs = expandedViewPrefs;
    if (sourceControlRootsChanged ||
        rightSidebarWidthsChanged ||
        workspacePanelsChanged) {
      workspacePrunedViewPrefs = expandedViewPrefs.copyWith(
        sourceControlRootByWorkspaceId: sourceControlRootsChanged
            ? prunedSourceControlRoots
            : expandedViewPrefs.sourceControlRootByWorkspaceId,
        rightSidebarWidthByWorkspaceId: rightSidebarWidthsChanged
            ? prunedRightSidebarWidths
            : expandedViewPrefs.rightSidebarWidthByWorkspaceId,
        workspacePanels: workspacePanelsChanged
            ? prunedWorkspacePanels
            : expandedViewPrefs.workspacePanels,
      );
    }
    final nextViewPrefs = workspacePrunedViewPrefs;
    final viewPrefsChanged =
        expansionChanged ||
        sourceControlRootsChanged ||
        rightSidebarWidthsChanged ||
        workspacePanelsChanged;
    state = state.copyWith(
      workspacesByProject: nextWorkspaces,
      viewPrefs: nextViewPrefs,
      activeProjectId: candidateProjectId,
      activeWorkspaceId: activeWorkspaceId,
      layoutByWorkspace: nextLayouts,
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        for (final entry in state.tabsByWorkspace.entries)
          if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
      },
      activeTabIdByWorkspace: <String, String>{
        for (final entry in state.activeTabIdByWorkspace.entries)
          if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
      },
    );
    _pruneWorktreeNavigationHistory();
    if (viewPrefsChanged) {
      unawaited(_persistViewPrefs());
    }
    _pruneExplorerSessions();
    _ensureSelectionHasTab();
    _pruneStaleWorkspacePrefs();
  }

  bool _workspaceInventoryReady() {
    if (!state.bootstrapped) {
      return false;
    }
    for (final project in state.projects) {
      if (!_workspaceSubs.containsKey(project.id) ||
          !state.workspacesByProject.containsKey(project.id)) {
        return false;
      }
    }
    return true;
  }

  void _pruneStaleWorkspacePrefs() {
    if (!_workspaceInventoryReady()) {
      return;
    }
    final liveWorkspaceIds = <String>{
      for (final workspaces in state.workspacesByProject.values)
        for (final workspace in workspaces) workspace.id,
    };
    final prefs = state.viewPrefs;
    final prunedSourceControlRoots = Map<String, String>.from(
      prefs.sourceControlRootByWorkspaceId,
    )..removeWhere((workspaceId, _) => !liveWorkspaceIds.contains(workspaceId));
    final prunedRightSidebarWidths = Map<String, double>.from(
      prefs.rightSidebarWidthByWorkspaceId,
    )..removeWhere((workspaceId, _) => !liveWorkspaceIds.contains(workspaceId));
    final prunedWorkspacePanels = Map<String, WorkspacePanel>.from(
      prefs.workspacePanels,
    )..removeWhere((workspaceId, _) => !liveWorkspaceIds.contains(workspaceId));
    final changed =
        prunedSourceControlRoots.length !=
            prefs.sourceControlRootByWorkspaceId.length ||
        prunedRightSidebarWidths.length !=
            prefs.rightSidebarWidthByWorkspaceId.length ||
        prunedWorkspacePanels.length != prefs.workspacePanels.length;
    if (!changed) {
      return;
    }
    state = state.copyWith(
      viewPrefs: prefs.copyWith(
        sourceControlRootByWorkspaceId: prunedSourceControlRoots,
        rightSidebarWidthByWorkspaceId: prunedRightSidebarWidths,
        workspacePanels: prunedWorkspacePanels,
      ),
    );
    unawaited(_persistViewPrefs());
  }

  void _onTabsChanged(String workspaceId, List<WorkspaceTabRecord> tabs) {
    _enqueueWorkspaceSync(() async {
      final incoming = _tabsWithoutClosedIds(tabs);
      final incomingIds = incoming.map((tab) => tab.id).toSet();
      final removed = state
          .tabsFor(workspaceId)
          .any((tab) => !incomingIds.contains(tab.id));
      final staleOwner = incoming.any(
        (tab) =>
            _transferredTabOwners.containsKey(tab.id) &&
            _transferredTabOwners[tab.id] != workspaceId,
      );
      if (!removed && !staleOwner) {
        _applyTabsChanged(workspaceId, incoming);
        return;
      }
      await _reconcileMigratedTabs(workspaceId);
      final live = _tabsWithoutClosedIds(
        await _repository.listWorkspaceTabs(workspaceId),
      );
      final layout = await _repository.findWorkbenchLayout(workspaceId);
      if (_disposed) return;
      if (layout != null) await _applyLayout(layout, persist: false);
      _applyTabsChanged(workspaceId, live);
    });
  }

  void _applyTabsChanged(String workspaceId, List<WorkspaceTabRecord> tabs) {
    if (!_tabSubProjectIds.containsKey(workspaceId)) {
      return;
    }
    final liveTabs = _tabsWithoutClosedIds(tabs);
    final liveTabIds = <String>{for (final tab in liveTabs) tab.id};
    final removedTabs = state
        .tabsFor(workspaceId)
        .where((tab) => !liveTabIds.contains(tab.id))
        .toList(growable: false);
    final workspace = _workspaceById(workspaceId);
    if (workspace != null) {
      _releaseHostedReviewTabsInBackground(workspace, removedTabs);
    }
    // A tab record that disappeared from persisted state can never reach its
    // live terminal handle again, so the emulator buffer and the editor
    // document have to go now. Release rather than close: the PTY may still
    // belong to whichever client removed the record.
    final runtime = ref.read(terminalRuntimeProvider);
    final editorSessions = ref.read(editorSessionRegistryProvider);
    for (final tab in removedTabs) {
      _transferredTabOwners.remove(tab.id);
      runtime.releaseTab(tab.id);
      editorSessions.forget(tab.id);
      if (tab.kind == WorkspaceTabKind.terminal &&
          ref.exists(agentHookReceiverProvider)) {
        // The host may already have stopped the process before the explicit
        // close reaches this client. Its transcript poller still has to go.
        ref
            .read(agentHookReceiverProvider)
            .clearTerminalSession(tab.terminalSessionId);
      }
    }
    final nextTabs = Map<String, List<WorkspaceTabRecord>>.from(
      state.tabsByWorkspace,
    )..[workspaceId] = liveTabs;
    final storedPanel = state.viewPrefs.workspacePanels[workspaceId];
    if (storedPanel != null && removedTabs.isNotEmpty) {
      var panel = storedPanel;
      for (final tab in removedTabs) {
        panel = panel.closeKey(WorkspacePanel.tabKey(tab.id));
      }
      _saveWorkspacePanel(
        workspaceId,
        panel,
        recordFocus: false,
        requestTerminalFocus: false,
      );
    }
    if (_workspaceIdsWithClearedLayout.contains(workspaceId)) {
      final nextLayouts = Map<String, WorkbenchLayout>.from(
        state.layoutByWorkspace,
      )..remove(workspaceId);
      final activeTabs = Map<String, String>.from(state.activeTabIdByWorkspace)
        ..remove(workspaceId);
      final sleptTabs = liveTabs.isEmpty
          ? nextTabs
          : (Map<String, List<WorkspaceTabRecord>>.from(state.tabsByWorkspace)
              ..[workspaceId] = const <WorkspaceTabRecord>[]);
      state = state.copyWith(
        tabsByWorkspace: sleptTabs,
        layoutByWorkspace: nextLayouts,
        activeTabIdByWorkspace: activeTabs,
      );
      _pruneExplorerSessions();
      return;
    }
    final currentLayout = state.layoutFor(workspaceId);
    if (currentLayout == null) {
      state = state.copyWith(tabsByWorkspace: nextTabs);
      if (!_workspaceIdsWithClearedLayout.contains(workspaceId) &&
          !_loadingLayoutWorkspaceIds.contains(workspaceId)) {
        unawaited(_loadLayoutForWorkspace(workspaceId));
      }
      _pruneExplorerSessions();
      if (liveTabs.isNotEmpty) {
        _ensureSelectionHasTab();
      }
      return;
    }

    final layout = currentLayout.sanitize(liveTabs);
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[workspaceId] = layout;
    state = state.copyWith(
      tabsByWorkspace: nextTabs,
      layoutByWorkspace: nextLayouts,
    );
    if (layout != currentLayout) {
      _persistLayoutInBackground(layout);
    }
    _pruneExplorerSessions();
    if (liveTabs.isNotEmpty) {
      _ensureSelectionHasTab();
    }
  }
}
