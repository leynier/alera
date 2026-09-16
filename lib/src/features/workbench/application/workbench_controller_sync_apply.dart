part of 'workbench_controller.dart';

mixin _WorkbenchControllerSyncApply
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerInternalLayout,
        _WorkbenchControllerSync {
  @override
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

  @override
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

  @override
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
