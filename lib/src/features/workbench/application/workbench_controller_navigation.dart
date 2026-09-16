part of 'workbench_controller.dart';

mixin _WorkbenchControllerNavigation
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerProjects,
        _WorkbenchControllerProjectSelection,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerWorkspacePanelPanes,
        _WorkbenchControllerInternalLayout {
  Future<String> launchAgentProfileTab({
    required Workspace workspace,
    required String profileId,
    String? targetGroupId,
    String prompt = '',
  }) async {
    final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
    try {
      final launch = await _promptWorkspaceRuntimeClient.launchAgent(
        workspaceId: workspace.id,
        profileId: profileId,
        prompt: prompt,
        clientMutationId: _uuid.v4(),
        requireIdempotency: false,
      );
      await openPersistedWorkspaceTab(
        workspaceId: workspace.id,
        tabId: launch.tabId,
        targetGroupId: targetGroupId,
        sleepGeneration: sleepGeneration,
      );
      state = state.copyWith(error: null);
      return launch.tabId;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> openPersistedWorkspaceTab({
    required String workspaceId,
    required String tabId,
    String? targetGroupId,
    int? sleepGeneration,
  }) async {
    final generation =
        sleepGeneration ?? (_workspaceSleepGeneration[workspaceId] ?? 0);
    final existedBeforeRequest = state
        .tabsFor(workspaceId)
        .any((candidate) => candidate.id == tabId);
    final tab = await _repository.findWorkspaceTabById(tabId);
    if (_disposed) return;
    if (tab == null || tab.workspaceId != workspaceId) {
      throw StateError(
        'The created tab is no longer available in this workspace.',
      );
    }
    if (_isStaleWorkspaceOpen(workspaceId, generation) ||
        _isClosedTabId(tab.id)) {
      if (!existedBeforeRequest || _isClosedTabId(tab.id)) {
        await _discardStaleOpenedTab(tab);
      }
      throw StateError('Workspace is no longer available for a persisted tab');
    }
    final currentTabs = state.tabsFor(workspaceId);
    final tabs = <WorkspaceTabRecord>[
      for (final current in currentTabs) current.id == tabId ? tab : current,
      if (!currentTabs.any((current) => current.id == tabId)) tab,
    ];
    _setTabsForWorkspace(workspaceId, tabs);
    addTerminalToWorkspacePanel(
      workspaceId: workspaceId,
      tab: tab,
      tabs: tabs,
      previousTabs: currentTabs,
      targetGroupId: targetGroupId,
    );
    if (!_disposed && !_isStaleWorkspaceOpen(workspaceId, generation)) {
      await selectWorkspaceTab(workspaceId: workspaceId, tabId: tabId);
    }
  }

  Future<void> selectWorkspaceTab({
    required String workspaceId,
    required String tabId,
  }) async {
    final workspace = state.workspacesByProject.values
        .expand((workspaces) => workspaces)
        .where((workspace) => workspace.id == workspaceId)
        .firstOrNull;
    final project = workspace == null
        ? null
        : _projectById(state.projects, workspace.projectId);
    if (workspace == null || project == null) return;
    final sleepGeneration = _workspaceSleepGeneration[workspaceId] ?? 0;
    final selectionRevisionBeforeActivation =
        _panelSelectionRevisionByWorkspace[workspaceId] ?? 0;
    if (state.activeWorkspaceId != workspaceId) {
      await selectWorkspace(project: project, workspace: workspace);
    }
    if (_isStaleWorkspaceOpen(workspaceId, sleepGeneration) ||
        (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) >
            selectionRevisionBeforeActivation ||
        state.tabsFor(workspaceId).every((tab) => tab.id != tabId)) {
      return;
    }
    final groupId = state.layoutFor(workspaceId)?.groupIdForTab(tabId);
    _setActiveTabInternal(
      workspaceId: workspaceId,
      tabId: tabId,
      groupId: groupId,
    );
  }

  Future<void> goBack() async {
    _pruneWorktreeNavigationHistory();
    final target = _worktreeNavigationHistory.peekBack(
      isValid: _isLiveWorktreeNavigationTarget,
    );
    if (target == null) {
      return;
    }
    final project = _projectById(state.projects, target.projectId);
    final workspace = project == null
        ? null
        : state
              .workspacesFor(project.id)
              .where((candidate) => candidate.id == target.workspaceId)
              .firstOrNull;
    if (project == null || workspace == null) {
      _pruneWorktreeNavigationHistory();
      return;
    }
    await _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: true,
      recordHistory: false,
    );
    _worktreeNavigationHistory.commitBack(target);
    _notifyNavigationHistoryChanged();
  }

  Future<void> goForward() async {
    _pruneWorktreeNavigationHistory();
    final target = _worktreeNavigationHistory.peekForward(
      isValid: _isLiveWorktreeNavigationTarget,
    );
    if (target == null) {
      return;
    }
    final project = _projectById(state.projects, target.projectId);
    final workspace = project == null
        ? null
        : state
              .workspacesFor(project.id)
              .where((candidate) => candidate.id == target.workspaceId)
              .firstOrNull;
    if (project == null || workspace == null) {
      _pruneWorktreeNavigationHistory();
      return;
    }
    await _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: true,
      recordHistory: false,
    );
    _worktreeNavigationHistory.commitForward(target);
    _notifyNavigationHistoryChanged();
  }
}
