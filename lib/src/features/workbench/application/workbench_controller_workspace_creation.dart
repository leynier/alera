part of 'workbench_controller.dart';

/// Creates workspaces and initializes their first tabs without selecting them.
///
/// Kept separate from project lifecycle actions because the From Prompt flow
/// deliberately persists its agent terminal before the Setup terminal.
mixin _WorkbenchControllerWorkspaceCreation
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspaceReconciliation,
        _WorkbenchControllerTabOpening,
        _WorkbenchControllerProjects,
        _WorkbenchControllerProjectSelection,
        _WorkbenchControllerInternalLayout {
  Future<WorkspaceCreationResult> createWorkspace({
    bool useProjectCheckout = false,
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
    String? hostId,
    String? issueUrl,
  }) {
    return _createWorkspace(
      useProjectCheckout: useProjectCheckout,
      project: project,
      sourceBranch: sourceBranch,
      newBranchName: newBranchName,
      reuseExistingBranch: reuseExistingBranch,
      name: name,
      parentWorkspaceId: parentWorkspaceId,
      hostId: hostId,
      issueUrl: issueUrl,
      initializeTabs: true,
    );
  }

  /// Creates the workspace record for the From Prompt flow without opening a
  /// blank terminal or the deferred Setup tab. The agent profile launch creates
  /// its terminal first, then [completePromptWorkspaceCreation] synchronizes
  /// that tab and appends Setup.
  Future<WorkspaceCreationResult> createWorkspaceForPrompt({
    bool useProjectCheckout = false,
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required String name,
    String? parentWorkspaceId,
    String? hostId,
    String? issueUrl,
  }) {
    return _createWorkspace(
      useProjectCheckout: useProjectCheckout,
      project: project,
      sourceBranch: sourceBranch,
      newBranchName: newBranchName,
      reuseExistingBranch: false,
      name: name,
      parentWorkspaceId: parentWorkspaceId,
      hostId: hostId,
      issueUrl: issueUrl,
      initializeTabs: false,
    );
  }

  Future<WorkspaceCreationResult> _createWorkspace({
    required bool useProjectCheckout,
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    required bool initializeTabs,
    String? name,
    String? parentWorkspaceId,
    String? hostId,
    String? issueUrl,
  }) async {
    try {
      final result = useProjectCheckout
          ? await _workspaceService.createSharedWorkspace(
              project: project,
              name: name,
              hostId: hostId,
              issueUrl: issueUrl,
            )
          : await _workspaceService.createLinkedWorkspace(
              project: project,
              sourceBranch: sourceBranch,
              newBranchName: newBranchName,
              reuseExistingBranch: reuseExistingBranch,
              name: name,
              hostId: hostId,
              issueUrl: issueUrl,
            );
      _reconcileCreatedWorkspace(project, result.workspace);
      if (initializeTabs) {
        await _initializeCreatedWorkspace(
          workspace: result.workspace,
          ensureInitialTerminal: true,
          deferredSetup: result,
        );
      }
      final parentId = parentWorkspaceId?.trim();
      if (parentId != null && parentId.isNotEmpty) {
        try {
          await _workspaceGraphRepository.linkWorkspaces(
            parentWorkspaceId: parentId,
            childWorkspaceId: result.workspace.id,
          );
        } catch (error) {
          // The workspace itself was created successfully, so the failure is
          // reported as a warning on the result instead of failing the flow.
          state = state.copyWith(error: null);
          return WorkspaceCreationResult(
            workspace: result.workspace,
            setupReport: result.setupReport,
            parentLinkError: error.toString(),
            deferredSetupCommand: result.deferredSetupCommand,
          );
        }
      }
      state = state.copyWith(error: null);
      return result;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  /// Finishes a From Prompt workspace after the host has persisted the agent
  /// tab: seeds the panel, appends Setup, and records the agent as that
  /// workspace's active tab without changing the visible workspace.
  Future<void> completePromptWorkspaceCreation({
    required WorkspaceCreationResult creation,
    String? agentTabId,
    bool openDeferredSetup = true,
  }) async {
    final workspace = creation.workspace;
    if (state.projects.every(
      (candidate) => candidate.id != workspace.projectId,
    )) {
      throw StateError('Workspace project not found: ${workspace.projectId}');
    }
    final setupCommand = creation.deferredSetupCommand?.trim();
    final expectsPromptTab =
        agentTabId?.trim().isNotEmpty == true ||
        (setupCommand != null && setupCommand.isNotEmpty);
    await _initializeCreatedWorkspace(
      workspace: workspace,
      ensureInitialTerminal: !expectsPromptTab,
      deferredSetup: openDeferredSetup ? creation : null,
      preferredTabId: agentTabId,
    );
  }

  Future<void> _initializeCreatedWorkspace({
    required Workspace workspace,
    required bool ensureInitialTerminal,
    WorkspaceCreationResult? deferredSetup,
    String? preferredTabId,
  }) async {
    if (_disposed) {
      return;
    }
    if (ensureInitialTerminal) {
      await _ensurePrimaryTerminal(workspace, requireActive: false);
    }
    if (_disposed) {
      return;
    }
    final tabs = await _workspaceTabService.listTabs(workspace.id);
    if (_disposed) {
      return;
    }
    _setTabsForWorkspace(workspace.id, tabs);
    final layout = await _ensureWorkbenchLayout(workspace.id, tabs);
    if (_disposed) {
      return;
    }
    await _applyLayout(layout, persist: false);
    _seedNewWorkspacePanel(workspace.id);
    if (deferredSetup != null) {
      await _openDeferredSetupTab(deferredSetup);
    }
    final resolvedTabId = preferredTabId?.trim();
    if (resolvedTabId != null && resolvedTabId.isNotEmpty) {
      final groupId = state
          .layoutFor(workspace.id)
          ?.groupIdForTab(resolvedTabId);
      _setActiveTabInternal(
        workspaceId: workspace.id,
        tabId: resolvedTabId,
        groupId: groupId,
      );
    }
  }
}
