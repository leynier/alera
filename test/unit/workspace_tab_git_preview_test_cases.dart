part of 'workspace_tab_service_test.dart';

void _registerWorkspaceTabGitPreviewTests() {
  test('openOrCreateGitDiffTab marks a preview tab in payload', () async {
    final repository = _FakeWorkbenchRepository();
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final tab = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/main.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
    );

    expect(tab.kind, WorkspaceTabKind.gitDiff);
    expect(tab.isPreview, isTrue);
    expect(tab.isFilePreviewSlot, isTrue);
    expect(tab.filePath, 'lib/main.dart');
    expect(repository.tabs.single.isPreview, isTrue);
  });

  test('preview git open retargets the replaceable file preview tab', () async {
    final repository = _FakeWorkbenchRepository();
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final first = await service.openOrCreateEditorTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/a.dart',
      preview: true,
    );
    final second = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/b.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
      replacePreviewTabId: first.id,
    );

    expect(second.id, first.id);
    expect(second.kind, WorkspaceTabKind.gitDiff);
    expect(second.filePath, 'lib/b.dart');
    expect(second.title, 'b.dart unstaged');
    expect(second.isPreview, isTrue);
    expect(repository.tabs, hasLength(1));
  });

  test('preview file open retargets a git preview tab', () async {
    final repository = _FakeWorkbenchRepository();
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final first = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/a.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
    );
    final second = await service.openOrCreateEditorTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/b.dart',
      preview: true,
      replacePreviewTabId: first.id,
    );

    expect(second.id, first.id);
    expect(second.kind, WorkspaceTabKind.editor);
    expect(second.filePath, 'lib/b.dart');
    expect(second.isPreview, isTrue);
    expect(repository.tabs, hasLength(1));
  });

  test('preview git open retargets another git preview tab', () async {
    final repository = _FakeWorkbenchRepository();
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final first = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/a.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
    );
    final second = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/b.dart',
      area: GitChangeArea.staged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
      replacePreviewTabId: first.id,
    );

    expect(second.id, first.id);
    expect(second.filePath, 'lib/b.dart');
    expect(second.gitDiffArea, GitChangeArea.staged);
    expect(second.isPreview, isTrue);
    expect(repository.tabs, hasLength(1));
  });

  test('permanent git open of a preview path pins that tab', () async {
    final repository = _FakeWorkbenchRepository();
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final preview = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/a.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
    );
    final pinned = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/a.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
    );

    expect(pinned.id, preview.id);
    expect(pinned.isPreview, isFalse);
    expect(repository.tabs, hasLength(1));
    expect(repository.tabs.single.isPreview, isFalse);
  });

  test(
    'permanent all-changes open does not steal a file preview tab',
    () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final preview = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/a.dart',
        preview: true,
      );
      final allChanges = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: WorkspaceGitDiffScope.all,
        replacePreviewTabId: preview.id,
      );

      expect(allChanges.id, isNot(preview.id));
      expect(allChanges.isPreview, isFalse);
      expect(repository.tabs, hasLength(2));
      expect(
        repository.tabs.singleWhere((tab) => tab.id == preview.id).isPreview,
        isTrue,
      );
    },
  );

  test('preview commit diff retargets the replaceable preview tab', () async {
    final repository = _FakeWorkbenchRepository();
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final first = await service.openOrCreateGitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/a.dart',
      area: GitChangeArea.unstaged,
      scope: WorkspaceGitDiffScope.file,
      preview: true,
    );
    final second = await service.openOrCreateGitCommitDiffTab(
      workspaceId: 'workspace-1',
      relativePath: 'lib/b.dart',
      scope: WorkspaceGitDiffScope.file,
      commitOid: 'abc123456789',
      compareRef: 'abc1234',
      preview: true,
      replacePreviewTabId: first.id,
    );

    expect(second.id, first.id);
    expect(second.gitDiffSource, WorkspaceGitDiffSource.commit);
    expect(second.filePath, 'lib/b.dart');
    expect(second.isPreview, isTrue);
    expect(repository.tabs, hasLength(1));
  });
}
