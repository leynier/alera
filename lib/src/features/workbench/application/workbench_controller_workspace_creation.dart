part of 'workbench_controller.dart';

/// Creates workspaces and initializes their first tabs.
///
/// Kept separate from project lifecycle actions because the From Prompt flow
/// deliberately persists its agent terminal before the Setup terminal.
mixin _WorkbenchControllerWorkspaceCreation
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerTabOpening,
        _WorkbenchControllerProjects {
  Future<WorkspaceCreationResult> createWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) {
    return _createWorkspace(
      project: project,
      sourceBranch: sourceBranch,
      newBranchName: newBranchName,
      reuseExistingBranch: reuseExistingBranch,
      name: name,
      parentWorkspaceId: parentWorkspaceId,
      initializeTabs: true,
    );
  }

  /// Creates the workspace record for the From Prompt flow without opening a
  /// blank terminal or the deferred Setup tab. The agent profile launch creates
  /// its terminal first, then [completePromptWorkspaceCreation] synchronizes
  /// that tab and appends Setup.
  Future<WorkspaceCreationResult> createWorkspaceForPrompt({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required String name,
    String? parentWorkspaceId,
  }) {
    return _createWorkspace(
      project: project,
      sourceBranch: sourceBranch,
      newBranchName: newBranchName,
      reuseExistingBranch: false,
      name: name,
      parentWorkspaceId: parentWorkspaceId,
      initializeTabs: false,
    );
  }

  Future<WorkspaceCreationResult> _createWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    required bool initializeTabs,
    String? name,
    String? parentWorkspaceId,
  }) async {
    try {
      final result = await _workspaceService.createLinkedWorkspace(
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        reuseExistingBranch: reuseExistingBranch,
        name: name,
      );
      _reconcileCreatedWorkspace(project, result.workspace);
      if (initializeTabs) {
        await selectWorkspace(project: project, workspace: result.workspace);
        await _openDeferredSetupTab(result);
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

  /// Activates a workspace created from a prompt after the host has persisted
  /// the agent tab, then appends Setup and restores focus to the agent.
  Future<void> completePromptWorkspaceCreation({
    required WorkspaceCreationResult creation,
    String? agentTabId,
  }) async {
    final workspace = creation.workspace;
    final project = state.projects
        .where((candidate) => candidate.id == workspace.projectId)
        .firstOrNull;
    if (project == null) {
      throw StateError('Workspace Project Not Found: ${workspace.projectId}');
    }
    final setupCommand = creation.deferredSetupCommand?.trim();
    final expectsPromptTab =
        agentTabId?.trim().isNotEmpty == true ||
        (setupCommand != null && setupCommand.isNotEmpty);
    await _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: !expectsPromptTab,
    );
    await _openDeferredSetupTab(creation);
    final resolvedAgentTabId = agentTabId?.trim();
    if (resolvedAgentTabId != null && resolvedAgentTabId.isNotEmpty) {
      final groupId = state
          .layoutFor(workspace.id)
          ?.groupIdForTab(resolvedAgentTabId);
      _setActiveTabInternal(
        workspaceId: workspace.id,
        tabId: resolvedAgentTabId,
        groupId: groupId,
      );
    }
  }

  void _reconcileCreatedWorkspace(Project project, Workspace workspace) {
    final workspaces = List<Workspace>.from(state.workspacesFor(project.id));
    final index = workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index == -1) {
      workspaces.add(workspace);
    } else {
      workspaces[index] = workspace;
    }
    state = state.copyWith(
      workspacesByProject: Map<String, List<Workspace>>.from(
        state.workspacesByProject,
      )..[project.id] = workspaces,
    );
  }
}
