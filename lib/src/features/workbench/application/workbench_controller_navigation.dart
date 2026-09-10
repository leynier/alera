part of 'workbench_controller.dart';

mixin _WorkbenchControllerNavigation
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerProjects {
  Future<void> launchAgentProfileTab({
    required Workspace workspace,
    required String profileId,
    String? targetGroupId,
  }) async {
    try {
      final launch = await _promptWorkspaceRuntimeClient.launchAgent(
        workspaceId: workspace.id,
        profileId: profileId,
        clientMutationId: _uuid.v4(),
        requireIdempotency: false,
      );
      await openPersistedWorkspaceTab(
        workspaceId: workspace.id,
        tabId: launch.tabId,
        targetGroupId: targetGroupId,
      );
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> openPersistedWorkspaceTab({
    required String workspaceId,
    required String tabId,
    String? targetGroupId,
  }) async {
    final tab = await _repository.findWorkspaceTabById(tabId);
    if (_disposed) return;
    if (tab == null || tab.workspaceId != workspaceId) {
      throw StateError(
        'The created tab is no longer available in this workspace.',
      );
    }
    final currentTabs = state.tabsFor(workspaceId);
    final layout = _layoutForMutation(workspaceId, currentTabs);
    final tabs = <WorkspaceTabRecord>[
      for (final current in currentTabs) current.id == tabId ? tab : current,
      if (!currentTabs.any((current) => current.id == tabId)) tab,
    ];
    _setTabsForWorkspace(workspaceId, tabs);
    final currentGroupId = layout.groupIdForTab(tabId);
    final requestedGroupId =
        targetGroupId != null && layout.groups.containsKey(targetGroupId)
        ? targetGroupId
        : null;
    final nextLayout = switch ((requestedGroupId, currentGroupId)) {
      (final groupId?, null) => layout.addTabToGroup(
        groupId: groupId,
        tabId: tabId,
      ),
      (final groupId?, final assigned?) when groupId != assigned =>
        layout.moveTab(
          tabId: tabId,
          targetGroupId: groupId,
          zone: .center,
          newGroupId: groupId,
        ),
      (null, null) => layout.addTabToGroup(
        groupId: layout.activeGroupId,
        tabId: tabId,
      ),
      _ => null,
    };
    if (nextLayout != null) {
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
    }
    if (!_disposed) {
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
    if (state.activeWorkspaceId != workspaceId) {
      await selectWorkspace(project: project, workspace: workspace);
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
