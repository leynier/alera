part of 'workspace_tab_service.dart';

/// Opening git diff tabs, including replacement of the shared preview slot.
extension WorkspaceTabGitOpening on WorkspaceTabService {
  Future<WorkspaceTabRecord> openOrCreateGitDiffTab({
    required String workspaceId,
    String? relativePath,
    GitChangeArea? area,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    bool preview = false,
    String? replacePreviewTabId,
  }) async {
    final normalizedPath = relativePath == null
        ? null
        : _normalizeRelativePath(relativePath);
    final normalizedRoot = normalizeSourceControlRootRelativePath(gitDiffRoot);
    if (scope == WorkspaceGitDiffScope.file && area == null) {
      throw StateError('Git diff file tabs require an area.');
    }
    if (scope != WorkspaceGitDiffScope.all && normalizedPath == null) {
      throw StateError('Git diff file tabs require a file path.');
    }
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind != WorkspaceTabKind.gitDiff) {
        continue;
      }
      if (tab.gitDiffSource == WorkspaceGitDiffSource.workingTree &&
          tab.gitDiffScope == scope &&
          tab.filePath == normalizedPath &&
          tab.gitDiffRoot == normalizedRoot &&
          tab.gitDiffArea == area) {
        if (!preview && tab.isPreview) {
          return keepPreviewTab(tab.id);
        }
        return tab;
      }
    }
    final payload = <String, Object?>{
      workspaceTabGitDiffScopePayloadKey: scope.key,
      if (area != null) workspaceTabGitDiffAreaPayloadKey: area.key,
      workspaceTabGitDiffRootPayloadKey: ?normalizedRoot,
      workspaceTabFilePathPayloadKey: ?normalizedPath,
      if (preview) workspaceTabPreviewPayloadKey: true,
    };
    return _upsertGitDiffTab(
      workspaceId: workspaceId,
      existing: existing,
      preview: preview,
      replacePreviewTabId: replacePreviewTabId,
      title: _titleForGitDiff(
        scope: scope,
        path: normalizedPath,
        area: area,
        root: normalizedRoot,
      ),
      payload: payload,
    );
  }

  Future<WorkspaceTabRecord> openOrCreateGitCommitDiffTab({
    required String workspaceId,
    String? relativePath,
    String? oldPath,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    required String commitOid,
    String? parentOid,
    required String compareRef,
    String? subject,
    String? message,
    bool preview = false,
    String? replacePreviewTabId,
  }) async {
    final normalizedPath = relativePath == null
        ? null
        : _normalizeRelativePath(relativePath);
    final normalizedOldPath = oldPath == null
        ? null
        : _normalizeRelativePath(oldPath);
    final normalizedRoot = normalizeSourceControlRootRelativePath(gitDiffRoot);
    if (scope != WorkspaceGitDiffScope.all && normalizedPath == null) {
      throw StateError('Commit diff file tabs require a file path.');
    }
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind != WorkspaceTabKind.gitDiff ||
          tab.gitDiffSource != WorkspaceGitDiffSource.commit) {
        continue;
      }
      if (tab.gitDiffScope == scope &&
          tab.filePath == normalizedPath &&
          tab.gitDiffOldPath == normalizedOldPath &&
          tab.gitDiffRoot == normalizedRoot &&
          tab.gitDiffCommitOid == commitOid) {
        if (!preview && tab.isPreview) {
          return keepPreviewTab(tab.id);
        }
        return tab;
      }
    }
    final payload = <String, Object?>{
      workspaceTabGitDiffSourcePayloadKey: WorkspaceGitDiffSource.commit.key,
      workspaceTabGitDiffScopePayloadKey: scope.key,
      workspaceTabGitDiffCommitOidPayloadKey: commitOid,
      workspaceTabGitDiffCompareRefPayloadKey: compareRef,
      workspaceTabGitDiffParentOidPayloadKey: ?parentOid,
      workspaceTabGitDiffCommitSubjectPayloadKey: ?subject,
      workspaceTabGitDiffCommitMessagePayloadKey: ?message,
      workspaceTabGitDiffRootPayloadKey: ?normalizedRoot,
      workspaceTabFilePathPayloadKey: ?normalizedPath,
      workspaceTabGitDiffOldPathPayloadKey: ?normalizedOldPath,
      if (preview) workspaceTabPreviewPayloadKey: true,
    };
    return _upsertGitDiffTab(
      workspaceId: workspaceId,
      existing: existing,
      preview: preview,
      replacePreviewTabId: replacePreviewTabId,
      title: _titleForGitCommitDiff(
        scope: scope,
        path: normalizedPath,
        compareRef: compareRef,
      ),
      payload: payload,
    );
  }

  Future<WorkspaceTabRecord> openOrCreateGitPullRequestDiffTab({
    required String workspaceId,
    String? gitDiffRoot,
    required int pullRequestNumber,
    required String commitOid,
    required String parentOid,
    required String retentionId,
    String? subject,
  }) async {
    if (pullRequestNumber <= 0) {
      throw StateError('Pull request number must be positive.');
    }
    final normalizedRetentionId = retentionId.trim();
    if (normalizedRetentionId.isEmpty) {
      throw StateError('Hosted review retention id must not be empty.');
    }
    final normalizedRoot = normalizeSourceControlRootRelativePath(gitDiffRoot);
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind == WorkspaceTabKind.gitDiff &&
          tab.gitDiffSource == WorkspaceGitDiffSource.pullRequest &&
          tab.gitDiffRoot == normalizedRoot &&
          tab.gitDiffPullRequestNumber == pullRequestNumber &&
          tab.gitDiffCommitOid == commitOid &&
          tab.gitDiffParentOid == parentOid) {
        return tab;
      }
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.gitDiff,
      title: 'Pull request #$pullRequestNumber',
      createdAt: _now(),
      updatedAt: _now(),
      payload: <String, Object?>{
        workspaceTabGitDiffSourcePayloadKey:
            WorkspaceGitDiffSource.pullRequest.key,
        workspaceTabGitDiffScopePayloadKey: WorkspaceGitDiffScope.all.key,
        workspaceTabGitDiffCommitOidPayloadKey: commitOid,
        workspaceTabGitDiffParentOidPayloadKey: parentOid,
        workspaceTabGitDiffCompareRefPayloadKey: '#$pullRequestNumber',
        workspaceTabGitDiffPullRequestNumberPayloadKey: pullRequestNumber,
        workspaceTabGitDiffHostedReviewRetentionIdPayloadKey:
            normalizedRetentionId,
        workspaceTabGitDiffCommitSubjectPayloadKey: ?subject,
        workspaceTabGitDiffRootPayloadKey: ?normalizedRoot,
      },
    );
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  Future<WorkspaceTabRecord> _upsertGitDiffTab({
    required String workspaceId,
    required List<WorkspaceTabRecord> existing,
    required bool preview,
    required String? replacePreviewTabId,
    required String title,
    required Map<String, Object?> payload,
  }) async {
    if (preview) {
      final replace = _previewTabToReplace(existing, replacePreviewTabId);
      if (replace != null) {
        final next = replace.copyWith(
          kind: WorkspaceTabKind.gitDiff,
          title: title,
          updatedAt: _now(),
          payload: payload,
        );
        await _repository.upsertWorkspaceTab(next);
        return next;
      }
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.gitDiff,
      title: title,
      createdAt: _now(),
      updatedAt: _now(),
      payload: payload,
    );
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  String _titleForGitDiff({
    required WorkspaceGitDiffScope scope,
    required String? path,
    required GitChangeArea? area,
    required String? root,
  }) {
    return switch (scope) {
      WorkspaceGitDiffScope.all =>
        root == null ? 'All changes' : '${_titleForPath(root)} changes',
      WorkspaceGitDiffScope.fileAll => '${_titleForPath(path!)} changes',
      WorkspaceGitDiffScope.file =>
        '${_titleForPath(path!)} ${area!.label.toLowerCase()}',
    };
  }

  String _titleForGitCommitDiff({
    required WorkspaceGitDiffScope scope,
    required String? path,
    required String compareRef,
  }) {
    return switch (scope) {
      WorkspaceGitDiffScope.all => 'Commit $compareRef',
      WorkspaceGitDiffScope.file ||
      WorkspaceGitDiffScope.fileAll => '${_titleForPath(path!)} $compareRef',
    };
  }
}
