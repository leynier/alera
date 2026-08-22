part of 'workbench_controller.dart';

mixin _WorkbenchControllerPullRequestDiffTabs
    on _$WorkbenchController, _WorkbenchControllerInternals {
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
    WorkspaceTabRecord? newTab;
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.openOrCreateGitPullRequestDiffTab(
        workspaceId: workspace.id,
        gitDiffRoot: gitDiffRoot,
        pullRequestNumber: pullRequestNumber,
        commitOid: commitOid,
        parentOid: parentOid,
        retentionId: retentionId,
        subject: subject,
      );
      final alreadyOpen = previousTabs.any(
        (candidate) => candidate.id == tab.id,
      );
      if (!alreadyOpen) {
        newTab = tab;
      }
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
      final tabs = alreadyOpen
          ? previousTabs
          : <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      final nextLayout = alreadyOpen
          ? layout.setActiveTab(
              groupId: layout.groupIdForTab(tab.id) ?? groupId,
              tabId: tab.id,
            )
          : layout.addTabToGroup(groupId: groupId, tabId: tab.id);
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      if (!retainedByTab) {
        if (newTab case final tab?) {
          await _workspaceTabService.closeTab(tab.id);
        }
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
