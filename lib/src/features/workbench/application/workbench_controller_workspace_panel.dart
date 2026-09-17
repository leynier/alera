part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspacePanel
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerInternalLayout {
  final Map<String, Future<void>> _primaryTerminalLoads = {};

  @override
  void _maybeEnsurePrimaryTerminal(Workspace workspace) {
    if (!state.tabsFor(workspace.id).any(isPrimaryTerminalCandidate)) {
      unawaited(_ensurePrimaryTerminal(workspace));
    }
  }

  bool _canKeepPrimaryTerminal(Workspace workspace, {int? sleepGeneration}) {
    return !_disposed &&
        state.activeWorkspaceId == workspace.id &&
        !_closingTabWorkspaceIds.contains(workspace.id) &&
        !_workspaceIdsWithClearedLayout.contains(workspace.id) &&
        (sleepGeneration == null ||
            !_isStaleWorkspaceOpen(workspace.id, sleepGeneration));
  }

  void _adoptPrimaryTerminal(Workspace workspace, WorkspaceTabRecord tab) {
    if (_isClosedTabId(tab.id)) {
      unawaited(_discardStalePrimaryTerminal(workspace, tab));
      return;
    }
    final live = state
        .tabsFor(workspace.id)
        .where((existing) => existing.id != tab.id)
        .toList(growable: false);
    if (live.any(isPrimaryTerminalCandidate)) {
      unawaited(_discardStalePrimaryTerminal(workspace, tab));
      return;
    }
    final current = _tabsWithoutClosedIds(<WorkspaceTabRecord>[...live, tab]);
    if (!current.any((candidate) => candidate.id == tab.id)) {
      unawaited(_discardStalePrimaryTerminal(workspace, tab));
      return;
    }
    _setTabsForWorkspace(workspace.id, current);
    final panel = state
        .workspacePanelFor(workspace.id)
        .reconcile(
          current,
          preferredPrimaryId: tab.id,
          workspaceId: workspace.id,
        );
    _saveWorkspacePanel(workspace.id, panel, recordFocus: false);
    final persisted = _layoutForMutation(workspace.id, current);
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[workspace.id] = persisted;
    state = state.copyWith(layoutByWorkspace: nextLayouts);
    _persistLayoutInBackground(persisted);
  }

  Future<void> _ensurePrimaryTerminal(Workspace workspace) {
    final existing = _primaryTerminalLoads[workspace.id];
    if (existing != null) {
      return existing;
    }
    late final Future<void> load;
    load = () async {
      WorkspaceTabRecord? created;
      var retryAfterInvalidation = false;
      final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
      try {
        final tabs = await _workspaceTabService.listTabs(workspace.id);
        if (!_canKeepPrimaryTerminal(
          workspace,
          sleepGeneration: sleepGeneration,
        )) {
          retryAfterInvalidation =
              _canKeepPrimaryTerminal(workspace) &&
              !state.tabsFor(workspace.id).any(isPrimaryTerminalCandidate);
          return;
        }
        if (_tabsWithoutClosedIds(tabs).any(isPrimaryTerminalCandidate)) {
          return;
        }
        created = await _workspaceTabService.createTerminalTab(workspace.id);
        if (!_canKeepPrimaryTerminal(
              workspace,
              sleepGeneration: sleepGeneration,
            ) ||
            _isClosedTabId(created.id)) {
          await _discardStalePrimaryTerminal(workspace, created);
          retryAfterInvalidation =
              _canKeepPrimaryTerminal(workspace) &&
              !state.tabsFor(workspace.id).any(isPrimaryTerminalCandidate);
          return;
        }
        final live = state
            .tabsFor(workspace.id)
            .where((tab) => tab.id != created!.id)
            .toList(growable: false);
        if (live.any(isPrimaryTerminalCandidate)) {
          await _discardStalePrimaryTerminal(workspace, created);
          return;
        }
        _adoptPrimaryTerminal(workspace, created);
      } catch (error) {
        if (created != null) {
          await _discardStalePrimaryTerminal(workspace, created);
        }
        if (!_disposed) {
          state = state.copyWith(error: error.toString());
        }
      } finally {
        if (identical(_primaryTerminalLoads[workspace.id], load)) {
          _primaryTerminalLoads.remove(workspace.id);
        }
        if (retryAfterInvalidation &&
            _canKeepPrimaryTerminal(workspace) &&
            !state.tabsFor(workspace.id).any(isPrimaryTerminalCandidate)) {
          unawaited(_ensurePrimaryTerminal(workspace));
        }
      }
    }();
    _primaryTerminalLoads[workspace.id] = load;
    return load;
  }

  Future<void> _discardStalePrimaryTerminal(
    Workspace workspace,
    WorkspaceTabRecord tab,
  ) async {
    try {
      await _workspaceTabService.closeTab(tab.id);
    } catch (_) {
      // The replacement must not outlive a close or sleep even if persist fails.
    }
    ref.read(terminalRuntimeProvider).closeTab(tab.id);
    ref.read(editorSessionRegistryProvider).forget(tab.id);
  }

  @override
  void _seedNewWorkspacePanel(String workspaceId) {
    final tools = WorkspaceTool.uniqueInOrder(
      state.viewPrefs.newWorkspaceTools,
    );
    if (tools.isEmpty) {
      return;
    }
    final panel = state.workspacePanelFor(workspaceId);
    final alreadyHasTools = panel.occupiedKeys.any(
      (key) => WorkspaceTool.forKey(key) != null,
    );
    if (alreadyHasTools) {
      return;
    }
    _saveWorkspacePanel(
      workspaceId,
      panel.openToolsInOrder(tools),
      reveal: true,
    );
  }

  void selectWorkspacePanelKey(
    String workspaceId,
    String key, {
    String? groupId,
    bool recordSelection = true,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    if (!panel.occupiedKeys.contains(key) &&
        WorkspaceTool.forKey(key) == null) {
      return;
    }
    if (recordSelection) {
      _panelSelectionRevisionByWorkspace[workspaceId] =
          (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
    }
    final next = panel.select(key, groupId: groupId);
    _saveWorkspacePanel(
      workspaceId,
      next,
      reveal: next.treeForKey(key) == WorkspacePanelTree.right,
    );
    _focusPanelTerminal(workspaceId, key);
  }

  @override
  void _focusPanelTerminal(String workspaceId, String? key) {
    if (state.activeWorkspaceId != workspaceId) {
      return;
    }
    final id = WorkspacePanel.tabId(key);
    if (id == null) {
      return;
    }
    final runtime = ref.read(terminalRuntimeProvider);
    final session = runtime.peekSession(id);
    if (session != null) {
      session.requestFocus();
      return;
    }
    // Inactive tabs are not mounted yet, so the session only exists after
    // the new surface builds. Retry once that frame has landed. Unit tests
    // have no Flutter binding; skip the deferred focus there.
    final scheduler = _schedulerBindingOrNull;
    if (scheduler == null) {
      return;
    }
    scheduler.addPostFrameCallback((_) {
      if (_disposed || state.activeWorkspaceId != workspaceId) {
        return;
      }
      if (state.workspacePanelFor(workspaceId).focusedKey != key) {
        return;
      }
      runtime.peekSession(id)?.requestFocus();
    });
  }

  SchedulerBinding? get _schedulerBindingOrNull {
    try {
      return SchedulerBinding.instance;
    } catch (_) {
      return null;
    }
  }

  void closeWorkspaceTool(String workspaceId, WorkspaceTool tool) {
    final panel = state.workspacePanelFor(workspaceId).closeTool(tool);
    _saveWorkspacePanel(
      workspaceId,
      panel,
      reveal:
          state.activeWorkspaceId == workspaceId &&
          panel.focusedKey != null &&
          panel.treeForKey(panel.focusedKey!) == WorkspacePanelTree.right,
    );
  }
}
