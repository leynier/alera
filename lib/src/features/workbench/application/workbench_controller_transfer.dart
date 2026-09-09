part of 'workbench_controller.dart';

mixin _WorkbenchControllerTransfer
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspaceReconciliation,
        _WorkbenchControllerTabOpening,
        _WorkbenchControllerProjects {
  Future<WorkspaceCreationResult> handOffWorkspace({
    required Workspace workspace,
    required String branch,
    bool reuseExistingBranch = false,
    String? name,
  }) async {
    if (_transferringWorkspace) {
      throw StateError('A workspace transfer is already in progress');
    }
    _transferringWorkspace = true;
    try {
      await _workspaceSyncQueue;
      final result = await _workspaceService.handOffWorkspace(
        workspace: workspace,
        branch: branch,
        reuseExistingBranch: reuseExistingBranch,
        name: name,
      );
      final project = state.projects.firstWhere(
        (entry) => entry.id == workspace.projectId,
      );
      _transferWorkspaceContents(workspace, result.workspace);
      _reconcileCreatedWorkspace(project, result.workspace);
      await _selectWorkspace(
        project: project,
        workspace: result.workspace,
        ensureInitialTerminal: false,
      );
      final active = state.activeTabIdByWorkspace[result.workspace.id];
      await _openDeferredSetupTab(result);
      if (active != null) {
        _setActiveTabInternal(workspaceId: result.workspace.id, tabId: active);
      }
      state = state.copyWith(error: null);
      return result;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      await _finishWorkspaceTransfer(workspace.projectId);
    }
  }

  Future<Workspace> handOnWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    if (_transferringWorkspace) {
      throw StateError('A workspace transfer is already in progress');
    }
    final main = state
        .workspacesFor(project.id)
        .where((entry) => entry.isMain)
        .firstOrNull;
    if (main != null &&
        state
            .tabsFor(main.id)
            .any(
              (tab) => ref.read(editorSessionRegistryProvider).isDirty(tab.id),
            )) {
      throw StateError(
        'The main worktree has unsaved editor changes. Save them and commit or stash before Hand On.',
      );
    }
    _transferringWorkspace = true;
    try {
      await _workspaceSyncQueue;
      final result = await _workspaceService.handOnWorkspace(
        workspace: workspace,
        activeWorkspaceId: state.activeWorkspaceId,
      );
      _transferWorkspaceContents(workspace, result.workspace);
      _reconcileCreatedWorkspace(project, result.workspace);
      await _selectWorkspace(
        project: project,
        workspace: result.workspace,
        ensureInitialTerminal: false,
      );
      state = state.copyWith(error: null);
      return result.workspace;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      await _finishWorkspaceTransfer(workspace.projectId);
    }
  }

  Future<void> _finishWorkspaceTransfer(String projectId) async {
    // Refresh from the store; queued snapshots may predate the atomic move.
    final refresh = _refreshAfterTransfer;
    _refreshAfterTransfer = false;
    try {
      if (refresh) {
        final project = state.projects
            .where((entry) => entry.id == projectId)
            .firstOrNull;
        if (project != null) await _refreshProjectAfterTransfer(project);
      }
    } finally {
      _transferringWorkspace = false;
    }
  }

  void _transferWorkspaceContents(
    Workspace source,
    Workspace destination, {
    Set<String>? tabIds,
  }) {
    final sourceTabs = state
        .tabsFor(source.id)
        .where((tab) => tabIds == null || tabIds.contains(tab.id))
        .toList();
    if (sourceTabs.isEmpty) return;
    final moved = sourceTabs.map((tab) {
      final payload = Map<String, Object?>.from(tab.payload);
      for (final key in ['filePath', 'gitDiffRoot', 'workingDirectory']) {
        final path = payload[key];
        if (path is String &&
            (path == source.path || p.isWithin(source.path, path))) {
          payload[key] = p.join(
            destination.path,
            p.relative(path, from: source.path),
          );
        }
      }
      return tab.copyWith(workspaceId: destination.id, payload: payload);
    }).toList();
    final runtime = ref.read(terminalRuntimeProvider);
    for (final tab in moved) {
      if (tab.kind == WorkspaceTabKind.terminal &&
          runtime.peekSession(tab.id) != null) {
        runtime.sessionFor(workspace: destination, tab: tab);
      }
    }
    final movedIds = moved.map((tab) => tab.id).toSet();
    for (final id in movedIds) {
      _transferredTabOwners[id] = destination.id;
    }
    ref
        .read(editorSessionRegistryProvider)
        .transferDocuments(movedIds, source.path, destination.path);
    ref
        .read(agentStatusControllerProvider.notifier)
        .transferSessions(
          source.id,
          destination.id,
          moved
              .where((tab) => tab.kind == WorkspaceTabKind.terminal)
              .map((tab) => tab.terminalSessionId)
              .toSet(),
        );
    _tabFocusHistory.transfer(source.id, destination.id, movedIds);
    final activity = ref.read(workspaceActivityControllerProvider)[source.id];
    if (activity != null) {
      ref
          .read(workspaceActivityControllerProvider.notifier)
          .recordActivity(destination.id, activity);
    }
    final tabs = {
      ...state.tabsByWorkspace,
      source.id: state
          .tabsFor(source.id)
          .where((tab) => !movedIds.contains(tab.id))
          .toList(),
      destination.id: [
        ...state
            .tabsFor(destination.id)
            .where((tab) => !movedIds.contains(tab.id)),
        ...moved,
      ],
    };
    final layouts = {...state.layoutByWorkspace};
    final sourceLayout = layouts.remove(source.id);
    layouts[destination.id] = mergeWorkspaceTransferLayout(
      sourceId: source.id,
      destinationId: destination.id,
      sourceTabs: sourceTabs,
      destinationTabs: state.tabsFor(destination.id),
      source: sourceLayout,
      destination: layouts[destination.id],
    );
    if (tabs[source.id]!.isNotEmpty && sourceLayout != null) {
      layouts[source.id] = sourceLayout.sanitize(tabs[source.id]!);
    }
    final active = {...state.activeTabIdByWorkspace};
    final activeTab = active.remove(source.id);
    if (activeTab != null) active[destination.id] = activeTab;
    state = state.copyWith(
      tabsByWorkspace: tabs,
      layoutByWorkspace: layouts,
      activeTabIdByWorkspace: active,
    );
  }
}
