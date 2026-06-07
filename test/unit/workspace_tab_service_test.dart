import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceTabService', () {
    test(
      'ensureInitialTerminalTab creates the first terminal workspace tab when none exist',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21),
        );

        final tab = await service.ensureInitialTerminalTab('workspace-1');

        expect(tab.title, 'Terminal 1');
        expect(tab.terminalSessionId, tab.id);
        expect(repository.tabs.single.title, 'Terminal 1');
      },
    );

    test(
      'createTerminalTab picks the next available terminal ordinal',
      () async {
        final repository = _FakeWorkbenchRepository()
          ..tabs.addAll(<WorkspaceTabRecord>[
            WorkspaceTabRecord(
              id: 'tab-1',
              workspaceId: 'workspace-1',
              title: 'Terminal 1',
              createdAt: DateTime.utc(2026, 5, 21),
              updatedAt: DateTime.utc(2026, 5, 21),
            ),
            WorkspaceTabRecord(
              id: 'tab-3',
              workspaceId: 'workspace-1',
              title: 'Terminal 3',
              createdAt: DateTime.utc(2026, 5, 21),
              updatedAt: DateTime.utc(2026, 5, 21),
            ),
          ]);
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21, 1),
        );

        final tab = await service.createTerminalTab('workspace-1');

        expect(tab.title, 'Terminal 2');
        expect(tab.payload[workspaceTabTerminalSessionIdPayloadKey], tab.id);
        expect(
          repository.tabs.map((record) => record.title),
          contains('Terminal 2'),
        );
      },
    );

    test(
      'openOrCreateEditorTab creates an editor tab for a normalized path',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21, 1),
        );

        final tab = await service.openOrCreateEditorTab(
          workspaceId: 'workspace-1',
          relativePath: './lib\\src/main.dart',
        );

        expect(tab.kind, WorkspaceTabKind.editor);
        expect(tab.title, 'main.dart');
        expect(tab.filePath, 'lib/src/main.dart');
        expect(repository.tabs, hasLength(1));
        expect(repository.tabs.single.id, tab.id);
      },
    );

    test('openOrCreateEditorTab reuses an existing editor tab', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      final first = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/main.dart',
      );
      final second = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: './lib/main.dart',
      );

      expect(second.id, first.id);
      expect(repository.tabs, hasLength(1));
    });

    test('openOrCreateEditorTab ignores merman preview tabs', () async {
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
      final service = WorkspaceTabService(repository: repository);

      final editor = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'docs/diagram.mmd',
      );

      expect(editor.id, isNot('preview-tab'));
      expect(editor.isMermanPreview, isFalse);
      expect(repository.tabs, hasLength(2));
    });

    test(
      'openOrCreateMermanPreviewTab creates and reuses preview tabs',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(repository: repository);

        final first = await service.openOrCreateMermanPreviewTab(
          workspaceId: 'workspace-1',
          relativePath: './docs/diagram.mmd',
        );
        final second = await service.openOrCreateMermanPreviewTab(
          workspaceId: 'workspace-1',
          relativePath: 'docs/diagram.mmd',
        );

        expect(second.id, first.id);
        expect(first.title, 'diagram.mmd preview');
        expect(first.filePath, 'docs/diagram.mmd');
        expect(first.isMermanPreview, isTrue);
        expect(repository.tabs, hasLength(1));
      },
    );

    test('openOrCreatePdfTab creates and reuses a PDF tab', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final first = await service.openOrCreatePdfTab(
        workspaceId: 'workspace-1',
        relativePath: './docs\\guide.pdf',
      );
      final second = await service.openOrCreatePdfTab(
        workspaceId: 'workspace-1',
        relativePath: 'docs/guide.pdf',
      );

      expect(first.kind, WorkspaceTabKind.pdf);
      expect(first.title, 'guide.pdf');
      expect(first.filePath, 'docs/guide.pdf');
      expect(second.id, first.id);
      expect(repository.tabs, hasLength(1));
    });

    test('openOrCreatePdfTab upgrades an existing editor PDF tab', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.editor,
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

      final tab = await service.openOrCreatePdfTab(
        workspaceId: 'workspace-1',
        relativePath: './docs/guide.pdf',
      );

      expect(tab.id, 'tab-1');
      expect(tab.kind, WorkspaceTabKind.pdf);
      expect(tab.filePath, 'docs/guide.pdf');
      expect(tab.updatedAt, DateTime.utc(2026, 5, 21, 1));
      expect(repository.tabs, hasLength(1));
      expect(repository.tabs.single.kind, WorkspaceTabKind.pdf);
    });

    test('openOrCreateEditorTab upgrades an existing PDF tab', () async {
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

      final tab = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: './docs/guide.pdf',
      );

      expect(tab.id, 'tab-1');
      expect(tab.kind, WorkspaceTabKind.editor);
      expect(tab.filePath, 'docs/guide.pdf');
      expect(tab.updatedAt, DateTime.utc(2026, 5, 21, 1));
      expect(repository.tabs, hasLength(1));
      expect(repository.tabs.single.kind, WorkspaceTabKind.editor);
    });

    test('openOrCreatePdfTab rejects paths outside the workspace', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      await expectLater(
        service.openOrCreatePdfTab(
          workspaceId: 'workspace-1',
          relativePath: '../guide.pdf',
        ),
        throwsStateError,
      );
    });

    test('openOrCreateEditorTab rejects paths outside the workspace', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      await expectLater(
        service.openOrCreateEditorTab(
          workspaceId: 'workspace-1',
          relativePath: '../secrets.dart',
        ),
        throwsStateError,
      );
    });

    test('openOrCreateGitDiffTab creates and reuses file diff tabs', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final first = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        relativePath: './lib\\main.dart',
        area: GitChangeArea.unstaged,
        scope: WorkspaceGitDiffScope.file,
      );
      final second = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/main.dart',
        area: GitChangeArea.unstaged,
        scope: WorkspaceGitDiffScope.file,
      );

      expect(first.kind, WorkspaceTabKind.gitDiff);
      expect(first.title, 'main.dart unstaged');
      expect(first.filePath, 'lib/main.dart');
      expect(first.gitDiffScope, WorkspaceGitDiffScope.file);
      expect(first.gitDiffArea, GitChangeArea.unstaged);
      expect(second.id, first.id);
      expect(repository.tabs, hasLength(1));
    });

    test('openOrCreateGitDiffTab creates all changes tabs', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final tab = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: WorkspaceGitDiffScope.all,
      );

      expect(tab.kind, WorkspaceTabKind.gitDiff);
      expect(tab.title, 'All changes');
      expect(tab.filePath, isNull);
      expect(tab.gitDiffScope, WorkspaceGitDiffScope.all);
      expect(repository.tabs, hasLength(1));
    });

    test('openOrCreateGitDiffTab validates file diff payloads', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      await expectLater(
        service.openOrCreateGitDiffTab(
          workspaceId: 'workspace-1',
          relativePath: 'lib/main.dart',
          scope: WorkspaceGitDiffScope.file,
        ),
        throwsStateError,
      );
      await expectLater(
        service.openOrCreateGitDiffTab(
          workspaceId: 'workspace-1',
          area: GitChangeArea.staged,
          scope: WorkspaceGitDiffScope.file,
        ),
        throwsStateError,
      );
    });

    test(
      'updates open editor tab paths and titles after a file move',
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

        final updated = await service.updateEditorPathsAfterMove(
          workspaceId: 'workspace-1',
          oldRelativePath: 'docs/note.txt',
          newRelativePath: 'docs/renamed-note.txt',
        );

        expect(updated.updatedTabs.single.filePath, 'docs/renamed-note.txt');
        expect(updated.updatedTabs.single.title, 'renamed-note.txt');
        expect(updated.removedTabIds, isEmpty);
        expect(repository.tabs.single.filePath, 'docs/renamed-note.txt');
        expect(repository.tabs.single.title, 'renamed-note.txt');
      },
    );

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
                workspaceTabFileRolePayloadKey:
                    workspaceTabFileRoleMermanPreview,
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
                workspaceTabFileRolePayloadKey:
                    workspaceTabFileRoleMermanPreview,
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
                workspaceTabFileRolePayloadKey:
                    workspaceTabFileRoleMermanPreview,
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

        final updated = await service.updateEditorPathsAfterMove(
          workspaceId: 'workspace-1',
          oldRelativePath: 'docs/note.txt',
          newRelativePath: 'docs/renamed-note.txt',
        );

        expect(updated.updatedTabs.single.filePath, 'docs/renamed-note.txt');
        expect(updated.updatedTabs.single.title, 'renamed-note.txt unstaged');
        expect(updated.removedTabIds, isEmpty);
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

      final updated = await service.updateEditorPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/note.txt',
        newRelativePath: 'docs/renamed-note.txt',
      );

      expect(updated.isEmpty, isTrue);
      expect(repository.tabs.single.filePath, 'docs/note.txt');
      expect(repository.tabs.single.title, 'note.txt staged');
    });

    test('updates descendant editor tab paths after a folder move', () async {
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
            kind: WorkspaceTabKind.editor,
            title: 'readme.md',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'readme.md',
            },
          ),
        ]);
      final service = WorkspaceTabService(repository: repository);

      final updated = await service.updateEditorPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'src',
        newRelativePath: 'lib/src',
      );

      expect(updated.updatedTabs, hasLength(1));
      expect(updated.removedTabIds, isEmpty);
      expect(updated.updatedTabs.single.filePath, 'lib/src/main.dart');
      expect(repository.tabs.first.filePath, 'lib/src/main.dart');
      expect(repository.tabs.last.filePath, 'readme.md');
    });

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

      final updated = await service.updateEditorPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'docs/guide.pdf',
        newRelativePath: 'reference/guide.pdf',
      );

      expect(updated.updatedTabs.single.kind, WorkspaceTabKind.pdf);
      expect(updated.updatedTabs.single.filePath, 'reference/guide.pdf');
      expect(updated.updatedTabs.single.title, 'guide.pdf');
      expect(updated.removedTabIds, isEmpty);
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

        final updated = await service.updateEditorPathsAfterMove(
          workspaceId: 'workspace-1',
          oldRelativePath: 'docs/note.txt',
          newRelativePath: 'docs/note.pdf',
        );

        expect(updated.updatedTabs.single.kind, WorkspaceTabKind.pdf);
        expect(updated.updatedTabs.single.filePath, 'docs/note.pdf');
        expect(updated.updatedTabs.single.title, 'note.pdf');
        expect(updated.removedTabIds, isEmpty);
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

        final updated = await service.updateEditorPathsAfterMove(
          workspaceId: 'workspace-1',
          oldRelativePath: 'docs/guide.pdf',
          newRelativePath: 'docs/guide.txt',
        );

        expect(updated.updatedTabs.single.kind, WorkspaceTabKind.editor);
        expect(updated.updatedTabs.single.filePath, 'docs/guide.txt');
        expect(updated.updatedTabs.single.title, 'guide.txt');
        expect(updated.removedTabIds, isEmpty);
        expect(repository.tabs.single.kind, WorkspaceTabKind.editor);
      },
    );

    test('renames a tab and marks its title as manual', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            title: 'Terminal 1',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{'source': 'test'},
          ),
        );
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final tab = await service.renameTab(tabId: 'tab-1', title: '  API  ');

      expect(tab.title, 'API');
      expect(tab.updatedAt, DateTime.utc(2026, 5, 21, 1));
      expect(tab.hasManualTitle, isTrue);
      expect(tab.payload['source'], 'test');
      expect(repository.tabs.single.title, 'API');
      expect(repository.tabs.single.hasManualTitle, isTrue);
    });

    test('rejects a blank tab title when renaming', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      await expectLater(
        service.renameTab(tabId: 'tab-1', title: '   '),
        throwsStateError,
      );
    });

    test('rejects renaming a tab that does not exist', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      await expectLater(
        service.renameTab(tabId: 'missing-tab', title: 'API'),
        throwsStateError,
      );
    });
  });
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final List<WorkspaceTabRecord> tabs = <WorkspaceTabRecord>[];
  final Map<String, WorkbenchLayout> layouts = <String, WorkbenchLayout>{};

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async => null;

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    return layouts[workspaceId];
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    return tabs
        .where((tab) => tab.workspaceId == workspaceId)
        .toList(growable: false);
  }

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async =>
      const <Workspace>[];

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    tabs.removeWhere((tab) => tab.id == tabId);
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {}

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {}

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {}

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    layouts.remove(workspaceId);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    final index = tabs.indexWhere((record) => record.id == tab.id);
    if (index == -1) {
      tabs.add(tab);
    } else {
      tabs[index] = tab;
    }
    return tab;
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    layouts[layout.workspaceId] = layout;
    return layout;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async => workspace;

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) =>
      const Stream<List<WorkspaceTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}
