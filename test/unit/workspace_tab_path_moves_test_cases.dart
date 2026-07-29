part of 'workspace_tab_service_test.dart';

/// Retargeting open tabs after a file or folder moves on disk.
///
/// Split out of `workspace_tab_service_test.dart`, which keeps the cases for
/// opening, creating, renaming and closing tabs.
void _registerWorkspaceTabPathMoveTests() {
  test('updates open editor tab paths and titles after a file move', () async {
    final repository = _FakeWorkbenchRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: 'workspace-1',
          kind: WorkspaceTabKind.editor,
          title: 'note.txt',
          createdAt: DateTime.utc(2026, 5, 21),
          updatedAt: DateTime.utc(2026, 5, 21),
          payload: const <String, Object?>{
            workspaceTabFilePathPayloadKey: 'docs/note.txt',
          },
        ),
      );
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final result = await service.updateFileTabPathsAfterMove(
      workspaceId: 'workspace-1',
      oldRelativePath: 'docs/note.txt',
      newRelativePath: 'docs/renamed-note.txt',
    );

    final updated = result.updatedTabs;
    expect(updated.single.filePath, 'docs/renamed-note.txt');
    expect(updated.single.title, 'renamed-note.txt');
    expect(result.closedTabIds, isEmpty);
    expect(repository.tabs.single.filePath, 'docs/renamed-note.txt');
    expect(repository.tabs.single.title, 'renamed-note.txt');
  });

  test('updates descendant file tab paths after a folder move', () async {
    final repository = _FakeWorkbenchRepository()
      ..tabs.addAll(<WorkspaceTabRecord>[
        WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: 'workspace-1',
          kind: WorkspaceTabKind.editor,
          title: 'main.dart',
          createdAt: DateTime.utc(2026, 5, 21),
          updatedAt: DateTime.utc(2026, 5, 21),
          payload: const <String, Object?>{
            workspaceTabFilePathPayloadKey: 'src/main.dart',
          },
        ),
        WorkspaceTabRecord(
          id: 'tab-2',
          workspaceId: 'workspace-1',
          kind: WorkspaceTabKind.markdownViewer,
          title: 'readme.md',
          createdAt: DateTime.utc(2026, 5, 21),
          updatedAt: DateTime.utc(2026, 5, 21),
          payload: const <String, Object?>{
            workspaceTabFilePathPayloadKey: 'src/readme.md',
          },
        ),
      ]);
    final service = WorkspaceTabService(repository: repository);

    final result = await service.updateFileTabPathsAfterMove(
      workspaceId: 'workspace-1',
      oldRelativePath: 'src',
      newRelativePath: 'lib/src',
    );

    final updated = result.updatedTabs;
    expect(updated, hasLength(2));
    expect(updated.map((tab) => tab.filePath), <String>[
      'lib/src/main.dart',
      'lib/src/readme.md',
    ]);
    expect(result.closedTabIds, isEmpty);
    expect(repository.tabs.first.filePath, 'lib/src/main.dart');
    expect(repository.tabs.last.filePath, 'lib/src/readme.md');
  });

  test(
    'updates merman preview tab paths and keeps preview titles after a file move',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
            title: 'diagram.mmd preview',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/diagram.mmd',
              workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
            },
          ),
        );
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final updated = await service.updateEditorPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/diagram.mmd',
        newRelativePath: 'docs/renamed.mmd',
      );

      expect(updated.updatedTabs.single.filePath, 'docs/renamed.mmd');
      expect(updated.updatedTabs.single.title, 'renamed.mmd preview');
      expect(updated.updatedTabs.single.isMermanPreview, isTrue);
      expect(updated.removedTabIds, isEmpty);
    },
  );

  test(
    'converts stale merman preview tabs to editor tabs after a non-merman rename',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'preview-tab',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
            title: 'diagram.mmd preview',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/diagram.mmd',
              workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
            },
          ),
        );
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final updated = await service.updateEditorPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/diagram.mmd',
        newRelativePath: 'docs/diagram.txt',
      );

      expect(updated.removedTabIds, isEmpty);
      expect(updated.updatedTabs.single.id, 'preview-tab');
      expect(updated.updatedTabs.single.filePath, 'docs/diagram.txt');
      expect(updated.updatedTabs.single.title, 'diagram.txt');
      expect(updated.updatedTabs.single.isMermanPreview, isFalse);
      expect(
        updated.updatedTabs.single.payload,
        isNot(contains(workspaceTabFileRolePayloadKey)),
      );

      final editor = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'docs/diagram.txt',
      );

      expect(editor.id, 'preview-tab');
      expect(repository.tabs, hasLength(1));
    },
  );

  test(
    'removes redundant preview tabs when a merman file is renamed to a text file with an editor open',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.addAll(<WorkspaceTabRecord>[
          WorkspaceTabRecord(
            id: 'editor-tab',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
            title: 'diagram.mmd',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/diagram.mmd',
            },
          ),
          WorkspaceTabRecord(
            id: 'preview-tab',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
            title: 'diagram.mmd preview',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/diagram.mmd',
              workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
            },
          ),
        ]);
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final updated = await service.updateEditorPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/diagram.mmd',
        newRelativePath: 'docs/diagram.txt',
      );

      expect(updated.removedTabIds, <String>['preview-tab']);
      expect(updated.updatedTabs.single.id, 'editor-tab');
      expect(updated.updatedTabs.single.filePath, 'docs/diagram.txt');
      expect(updated.updatedTabs.single.title, 'diagram.txt');
      expect(repository.tabs, hasLength(1));
      expect(repository.tabs.single.id, 'editor-tab');
    },
  );

  test(
    'updates open git diff tab paths and titles after a file move',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.gitDiff,
            title: 'note.txt unstaged',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/note.txt',
              workspaceTabGitDiffScopePayloadKey: 'file',
              workspaceTabGitDiffAreaPayloadKey: 'unstaged',
            },
          ),
        );
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final result = await service.updateFileTabPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/note.txt',
        newRelativePath: 'docs/renamed-note.txt',
      );

      final updated = result.updatedTabs;
      expect(updated.single.filePath, 'docs/renamed-note.txt');
      expect(updated.single.title, 'renamed-note.txt unstaged');
      expect(result.closedTabIds, isEmpty);
      expect(repository.tabs.single.filePath, 'docs/renamed-note.txt');
      expect(repository.tabs.single.title, 'renamed-note.txt unstaged');
    },
  );

  test('keeps staged git diff tab paths after a file move', () async {
    final repository = _FakeWorkbenchRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: 'workspace-1',
          kind: WorkspaceTabKind.gitDiff,
          title: 'note.txt staged',
          createdAt: DateTime.utc(2026, 5, 21),
          updatedAt: DateTime.utc(2026, 5, 21),
          payload: const <String, Object?>{
            workspaceTabFilePathPayloadKey: 'docs/note.txt',
            workspaceTabGitDiffScopePayloadKey: 'file',
            workspaceTabGitDiffAreaPayloadKey: 'staged',
          },
        ),
      );
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final result = await service.updateFileTabPathsAfterMove(
      workspaceId: 'workspace-1',
      oldRelativePath: 'docs/note.txt',
      newRelativePath: 'docs/renamed-note.txt',
    );

    expect(result.updatedTabs, isEmpty);
    expect(result.closedTabIds, isEmpty);
    expect(repository.tabs.single.filePath, 'docs/note.txt');
    expect(repository.tabs.single.title, 'note.txt staged');
  });

  test('updates staged git diff paths when their root moves', () async {
    final repository = _FakeWorkbenchRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: 'workspace-1',
          kind: WorkspaceTabKind.gitDiff,
          title: 'main.dart staged',
          createdAt: DateTime.utc(2026, 5, 21),
          updatedAt: DateTime.utc(2026, 5, 21),
          payload: const <String, Object?>{
            workspaceTabFilePathPayloadKey: 'packages/app/lib/main.dart',
            workspaceTabGitDiffScopePayloadKey: 'file',
            workspaceTabGitDiffAreaPayloadKey: 'staged',
            workspaceTabGitDiffRootPayloadKey: 'packages/app',
          },
        ),
      );
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final result = await service.updateFileTabPathsAfterMove(
      workspaceId: 'workspace-1',
      oldRelativePath: 'packages',
      newRelativePath: 'modules',
    );

    expect(result.updatedTabs, hasLength(1));
    expect(result.updatedTabs.single.filePath, 'modules/app/lib/main.dart');
    expect(result.updatedTabs.single.gitDiffRoot, 'modules/app');
    expect(repository.tabs.single.filePath, 'modules/app/lib/main.dart');
    expect(repository.tabs.single.gitDiffRoot, 'modules/app');
  });

  test(
    'closes markdown viewer tabs when a file move removes the md extension',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.addAll(<WorkspaceTabRecord>[
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
            title: 'readme.md',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/readme.md',
            },
          ),
          WorkspaceTabRecord(
            id: 'tab-2',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.markdownViewer,
            title: 'readme.md',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/readme.md',
            },
          ),
        ]);
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final result = await service.updateFileTabPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/readme.md',
        newRelativePath: 'docs/readme.txt',
      );

      expect(result.closedTabIds, <String>['tab-2']);
      expect(result.updatedTabs.single.kind, WorkspaceTabKind.editor);
      expect(result.updatedTabs.single.filePath, 'docs/readme.txt');
      expect(repository.tabs.map((tab) => tab.id), <String>['tab-1']);
      expect(repository.tabs.single.filePath, 'docs/readme.txt');
    },
  );

  test('updates open PDF tab paths and titles after a file move', () async {
    final repository = _FakeWorkbenchRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: 'workspace-1',
          kind: WorkspaceTabKind.pdf,
          title: 'guide.pdf',
          createdAt: DateTime.utc(2026, 5, 21),
          updatedAt: DateTime.utc(2026, 5, 21),
          payload: const <String, Object?>{
            workspaceTabFilePathPayloadKey: 'docs/guide.pdf',
          },
        ),
      );
    final service = WorkspaceTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 5, 21, 1),
    );

    final result = await service.updateFileTabPathsAfterMove(
      workspaceId: 'workspace-1',
      oldRelativePath: 'docs/guide.pdf',
      newRelativePath: 'reference/guide.pdf',
    );

    final updated = result.updatedTabs;
    expect(updated.single.kind, WorkspaceTabKind.pdf);
    expect(updated.single.filePath, 'reference/guide.pdf');
    expect(updated.single.title, 'guide.pdf');
    expect(result.closedTabIds, isEmpty);
    expect(repository.tabs.single.filePath, 'reference/guide.pdf');
  });

  test(
    'changes editor tab to PDF when a move gives it a PDF extension',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
            title: 'note.txt',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/note.txt',
            },
          ),
        );
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final result = await service.updateFileTabPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/note.txt',
        newRelativePath: 'docs/note.pdf',
      );

      final updated = result.updatedTabs;
      expect(updated.single.kind, WorkspaceTabKind.pdf);
      expect(updated.single.filePath, 'docs/note.pdf');
      expect(updated.single.title, 'note.pdf');
      expect(result.closedTabIds, isEmpty);
      expect(repository.tabs.single.kind, WorkspaceTabKind.pdf);
    },
  );

  test(
    'changes PDF tab to editor when a move removes the PDF extension',
    () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.pdf,
            title: 'guide.pdf',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'docs/guide.pdf',
            },
          ),
        );
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final result = await service.updateFileTabPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/guide.pdf',
        newRelativePath: 'docs/guide.txt',
      );

      final updated = result.updatedTabs;
      expect(updated.single.kind, WorkspaceTabKind.editor);
      expect(updated.single.filePath, 'docs/guide.txt');
      expect(updated.single.title, 'guide.txt');
      expect(result.closedTabIds, isEmpty);
      expect(repository.tabs.single.kind, WorkspaceTabKind.editor);
    },
  );
}
