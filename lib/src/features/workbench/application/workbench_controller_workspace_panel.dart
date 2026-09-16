part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspacePanel
    on _$WorkbenchController, _WorkbenchControllerInternals {
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
    // the new surface builds. Retry once that frame has landed.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed || state.activeWorkspaceId != workspaceId) {
        return;
      }
      if (state.workspacePanelFor(workspaceId).focusedKey != key) {
        return;
      }
      runtime.peekSession(id)?.requestFocus();
    });
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

  String _workspacePaneKey(String tabIdOrKey) {
    if (tabIdOrKey.startsWith('tab:') || tabIdOrKey.startsWith('tool:')) {
      return tabIdOrKey;
    }
    return WorkspacePanel.tabKey(tabIdOrKey);
  }

  void addTerminalToWorkspacePanel({
    required String workspaceId,
    required WorkspaceTabRecord tab,
    required List<WorkspaceTabRecord> tabs,
    required List<WorkspaceTabRecord> previousTabs,
    String? targetGroupId,
    bool focus = true,
  }) {
    final panel =
        (state.viewPrefs.workspacePanels[workspaceId] ?? const WorkspacePanel())
            .reconcile(
              previousTabs,
              preferredPrimaryId: state.layoutFor(workspaceId)?.activeTabId,
              workspaceId: workspaceId,
            );
    final key = WorkspacePanel.tabKey(tab.id);
    if (targetGroupId == null && panel.occupiedKeys.contains(key)) {
      if (focus) {
        _panelSelectionRevisionByWorkspace[workspaceId] =
            (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
      }
      final next = focus ? panel.select(key) : panel;
      _saveWorkspacePanel(
        workspaceId,
        next,
        reveal: focus && next.treeForKey(key) != WorkspacePanelTree.main,
        recordFocus: focus,
      );
      final persisted = _layoutForMutation(workspaceId, tabs);
      final nextLayouts = Map<String, WorkbenchLayout>.from(
        state.layoutByWorkspace,
      )..[workspaceId] = persisted;
      state = state.copyWith(layoutByWorkspace: nextLayouts);
      _persistLayoutInBackground(persisted);
      return;
    }
    final main = panel.ensuredMainLayout(workspaceId);
    final right = panel.ensuredLayout(workspaceId);
    final addToMain =
        targetGroupId != null && main.groups.containsKey(targetGroupId);
    final layout = addToMain ? main : right;
    final groupId =
        targetGroupId != null && layout.groups.containsKey(targetGroupId)
        ? targetGroupId
        : layout.activeGroupId;
    var source = panel;
    final currentGroupId = addToMain
        ? source.ensuredMainLayout(workspaceId).groupIdForTab(key)
        : source.ensuredLayout(workspaceId).groupIdForTab(key);
    if (targetGroupId != null && currentGroupId == groupId) {
      if (focus) {
        _panelSelectionRevisionByWorkspace[workspaceId] =
            (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
      }
      final next = focus ? source.select(key, groupId: groupId) : source;
      _saveWorkspacePanel(
        workspaceId,
        next,
        reveal: focus && !addToMain,
        recordFocus: focus,
      );
      final persisted = _layoutForMutation(workspaceId, tabs);
      final nextLayouts = Map<String, WorkbenchLayout>.from(
        state.layoutByWorkspace,
      )..[workspaceId] = persisted;
      state = state.copyWith(layoutByWorkspace: nextLayouts);
      _persistLayoutInBackground(persisted);
      return;
    }
    if (targetGroupId != null &&
        source.treeForKey(key) != null &&
        currentGroupId != groupId) {
      source = source.closeKey(key);
    }
    final placedLayout = addToMain
        ? source.ensuredMainLayout(workspaceId)
        : source.ensuredLayout(workspaceId);
    final placed = placedLayout.addTabToGroup(groupId: groupId, tabId: key);
    final next = addToMain
        ? source.applyMainLayout(placed)
        : source.applyPaneLayout(placed);
    if (focus) {
      _panelSelectionRevisionByWorkspace[workspaceId] =
          (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
    }
    _saveWorkspacePanel(
      workspaceId,
      focus ? next.copyWith(focusedKey: key) : next,
      reveal: focus && !addToMain,
      recordFocus: focus,
    );
    final persisted = _layoutForMutation(workspaceId, tabs);
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[workspaceId] = persisted;
    state = state.copyWith(layoutByWorkspace: nextLayouts);
    _persistLayoutInBackground(persisted);
  }

  Future<void> moveWorkspacePaneTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    WorkspacePanelTree source = WorkspacePanelTree.right,
    WorkspacePanelTree target = WorkspacePanelTree.right,
    int? index,
  }) async {
    final panel = state.workspacePanelFor(workspaceId);
    final key = _workspacePaneKey(tabId);
    final newGroupId = _newPaneGroupId();
    final WorkspacePanel next;
    if (source == target) {
      final layout = source == WorkspacePanelTree.main
          ? panel.ensuredMainLayout(workspaceId)
          : panel.ensuredLayout(workspaceId);
      final moved = layout.moveTab(
        tabId: key,
        targetGroupId: targetGroupId,
        zone: zone,
        newGroupId: newGroupId,
        index: index,
      );
      next = source == WorkspacePanelTree.main
          ? panel.applyMainLayout(moved)
          : panel.applyPaneLayout(moved);
    } else {
      next = panel.moveKey(
        key: key,
        target: target,
        targetGroupId: targetGroupId,
        zone: zone,
        newGroupId: newGroupId,
        index: index,
      );
    }
    _panelSelectionRevisionByWorkspace[workspaceId] =
        (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
    _saveWorkspacePanel(
      workspaceId,
      next.copyWith(focusedKey: key),
      reveal: target == WorkspacePanelTree.right,
    );
    state = state.copyWith(error: null);
  }

  Future<WorkspaceTabRecord> splitWorkspacePaneWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    WorkspaceTabRecord? created;
    try {
      final panel = state.workspacePanelFor(workspace.id);
      final addToMain = panel
          .ensuredMainLayout(workspace.id)
          .groups
          .containsKey(groupId);
      final targetLayout = addToMain
          ? panel.ensuredMainLayout(workspace.id)
          : panel.ensuredLayout(workspace.id);
      if (!targetLayout.groups.containsKey(groupId)) {
        throw StateError('Unknown pane group: $groupId');
      }
      final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
      created = await _workspaceTabService.createTerminalTab(workspace.id);
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration) ||
          _isClosedTabId(created.id)) {
        await _discardStalePrimaryTerminal(workspace, created);
        throw StateError('Workspace is no longer available for split');
      }
      final live = state
          .tabsFor(workspace.id)
          .where((tab) => tab.id != created!.id)
          .toList(growable: false);
      final tabs = <WorkspaceTabRecord>[...live, created];
      _setTabsForWorkspace(workspace.id, tabs);
      final current = state.workspacePanelFor(workspace.id);
      final key = WorkspacePanel.tabKey(created.id);
      var layout = addToMain
          ? current.ensuredMainLayout(workspace.id)
          : current.ensuredLayout(workspace.id);
      if (layout.groupIdForTab(key) != null) {
        layout = layout.removeTab(key);
      }
      if (!layout.groups.containsKey(groupId)) {
        await _discardStalePrimaryTerminal(workspace, created);
        throw StateError('Unknown pane group: $groupId');
      }
      final split = layout.splitWithGroup(
        targetGroupId: groupId,
        zone: zone,
        newGroup: WorkbenchPaneGroup(
          id: _newPaneGroupId(),
          tabIds: <String>[key],
          activeTabId: key,
        ),
      );
      final next = addToMain
          ? current.applyMainLayout(split)
          : current.applyPaneLayout(split);
      _panelSelectionRevisionByWorkspace[workspace.id] =
          (_panelSelectionRevisionByWorkspace[workspace.id] ?? 0) + 1;
      _saveWorkspacePanel(
        workspace.id,
        next.copyWith(focusedKey: key),
        reveal: !addToMain,
      );
      final persisted = _layoutForMutation(workspace.id, tabs);
      final nextLayouts = Map<String, WorkbenchLayout>.from(
        state.layoutByWorkspace,
      )..[workspace.id] = persisted;
      state = state.copyWith(layoutByWorkspace: nextLayouts);
      _persistLayoutInBackground(persisted);
      return created;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  void mergeWorkspacePaneIntoSibling({
    required String workspaceId,
    required String groupId,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    final main = panel.ensuredMainLayout(workspaceId);
    if (main.groups.containsKey(groupId)) {
      if (main.groups.length < 2) {
        return;
      }
      final next = panel.applyMainLayout(main.mergeGroupIntoSibling(groupId));
      final focused = next.focusedKey;
      _saveWorkspacePanel(
        workspaceId,
        focused == null ? next : next.select(focused),
      );
      state = state.copyWith(error: null);
      return;
    }
    final layout = panel.ensuredLayout(workspaceId);
    if (layout.groups.length < 2) {
      return;
    }
    final next = panel.applyPaneLayout(layout.mergeGroupIntoSibling(groupId));
    final focused = next.focusedKey;
    _saveWorkspacePanel(
      workspaceId,
      focused == null ? next : next.select(focused),
    );
    state = state.copyWith(error: null);
  }

  void updateWorkspacePaneSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
    WorkspacePanelTree tree = WorkspacePanelTree.right,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    if (tree == WorkspacePanelTree.main) {
      _saveWorkspacePanel(
        workspaceId,
        panel.applyMainLayout(
          panel
              .ensuredMainLayout(workspaceId)
              .updateSplitRatio(nodePath, ratio),
        ),
      );
      return;
    }
    _saveWorkspacePanel(
      workspaceId,
      panel.applyPaneLayout(
        panel.ensuredLayout(workspaceId).updateSplitRatio(nodePath, ratio),
      ),
    );
  }
}
