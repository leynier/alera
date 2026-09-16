part of 'workbench_controller.dart';

mixin _WorkbenchControllerPullRequestDiffTabs
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerInternalLayout {
  Future<WorkspaceTabRecord> openGitPullRequestDiffTab({
    required Workspace workspace,
    String? gitDiffRoot,
    required int pullRequestNumber,
    required String commitOid,
    required String parentOid,
    required String retentionId,
    String? subject,
    String? targetGroupId,
  }) async {
    var retainedByTab = false;
    WorkspaceTabRecord? createdTab;
    var existedBeforeRequest = false;
    final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
    try {
      final previousIds = <String>{
        for (final candidate in state.tabsFor(workspace.id)) candidate.id,
      };
      final tab = await _workspaceTabService.openOrCreateGitPullRequestDiffTab(
        workspaceId: workspace.id,
        gitDiffRoot: gitDiffRoot,
        pullRequestNumber: pullRequestNumber,
        commitOid: commitOid,
        parentOid: parentOid,
        retentionId: retentionId,
        subject: subject,
      );
      createdTab = tab;
      existedBeforeRequest = previousIds.contains(tab.id);
      if (tab.gitDiffHostedReviewRetentionId == retentionId) {
        await _persistHostedReviewRetention(
          workspace: workspace,
          relativeRoot: gitDiffRoot,
          retentionId: retentionId,
        );
        retainedByTab = true;
      } else {
        await _releaseHostedReviewRetention(
          workspace: workspace,
          relativeRoot: gitDiffRoot,
          retentionId: retentionId,
        );
      }
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration) ||
          _closedTabIds.contains(tab.id)) {
        throw StateError('Workspace is no longer available for a review tab');
      }
      final live = state.tabsFor(workspace.id);
      final tabs =
          existedBeforeRequest ||
              live.any((candidate) => candidate.id == tab.id)
          ? live
                .map((candidate) => candidate.id == tab.id ? tab : candidate)
                .toList(growable: false)
          : <WorkspaceTabRecord>[...live, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      _selectOpenedWorkspaceTab(
        workspaceId: workspace.id,
        tab: tab,
        existedBeforeRequest: existedBeforeRequest,
        targetGroupId: targetGroupId,
      );
      final persisted = _layoutForMutation(workspace.id, tabs);
      await _applyLayout(persisted, persist: true);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      final canceled =
          _isStaleWorkspaceOpen(workspace.id, sleepGeneration) ||
          (createdTab != null && _closedTabIds.contains(createdTab.id));
      if (createdTab case final tab?
          when !existedBeforeRequest && (canceled || !retainedByTab)) {
        await _discardStaleOpenedTab(tab);
      }
      if (!retainedByTab || (canceled && !existedBeforeRequest)) {
        await _releaseHostedReviewRetention(
          workspace: workspace,
          relativeRoot: gitDiffRoot,
          retentionId: retentionId,
        );
      }
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }
}
