import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

part 'workspace_tab_path_moves_test_cases.dart';

void main() {
  group('WorkspaceTabService', () {
    _registerWorkspaceTabPathMoveTests();

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
    test('createTerminalTab builds a named one-shot setup terminal', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21),
      );

      final tab = await service.createTerminalTab(
        'workspace-1',
        title: '  Setup  ',
        initialCommand: '  /bin/sh "/run/alera/worktree-setup-ws.sh"  ',
        spawnOnCreate: true,
        initialCommandOnce: true,
        autoCloseOnSuccess: true,
      );

      expect(tab.title, 'Setup');
      // Pinned, so a title the setup command emits over OSC cannot rename it.
      expect(tab.hasManualTitle, isTrue);
      expect(tab.initialCommand, '/bin/sh "/run/alera/worktree-setup-ws.sh"');
      expect(tab.initialCommandOnce, isTrue);
      expect(tab.spawnOnCreate, isTrue);
      expect(tab.autoCloseOnSuccess, isTrue);
      expect(repository.tabs.single.title, 'Setup');
    });

    test(
      'createTerminalTab leaves an ordinal terminal free of setup payload keys',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21),
        );

        final tab = await service.createTerminalTab('workspace-1');

        expect(tab.title, 'Terminal 1');
        expect(tab.hasManualTitle, isFalse);
        expect(tab.initialCommand, isNull);
        expect(tab.initialCommandOnce, isFalse);
        expect(tab.spawnOnCreate, isFalse);
        expect(tab.autoCloseOnSuccess, isFalse);
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

    test(
      'openOrCreateMarkdownViewerTab creates and reuses a markdown viewer tab',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21, 1),
        );

        final first = await service.openOrCreateMarkdownViewerTab(
          workspaceId: 'workspace-1',
          relativePath: './docs\\readme.md',
        );
        final second = await service.openOrCreateMarkdownViewerTab(
          workspaceId: 'workspace-1',
          relativePath: 'docs/readme.md',
        );

        expect(first.kind, WorkspaceTabKind.markdownViewer);
        expect(first.title, 'readme.md');
        expect(first.filePath, 'docs/readme.md');
        expect(second.id, first.id);
        expect(repository.tabs, hasLength(1));
      },
    );

    test('openOrCreateMarkdownViewerTab rejects non-markdown paths', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(repository: repository);

      await expectLater(
        service.openOrCreateMarkdownViewerTab(
          workspaceId: 'workspace-1',
          relativePath: 'lib/main.dart',
        ),
        throwsStateError,
      );
    });

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

    test('openOrCreateGitDiffTab scopes tabs by git diff root', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final rootTab = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: WorkspaceGitDiffScope.all,
        gitDiffRoot: './packages\\app',
      );
      final workspaceTab = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: WorkspaceGitDiffScope.all,
      );
      final rootAgain = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: WorkspaceGitDiffScope.all,
        gitDiffRoot: 'packages/app',
      );

      expect(rootTab.title, 'app changes');
      expect(rootTab.gitDiffRoot, 'packages/app');
      expect(workspaceTab.gitDiffRoot, isNull);
      expect(rootAgain.id, rootTab.id);
      expect(repository.tabs, hasLength(2));
    });

    test(
      'openOrCreateGitCommitDiffTab creates and reuses commit diff tabs independently',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21, 1),
        );

        final workingTreeTab = await service.openOrCreateGitDiffTab(
          workspaceId: 'workspace-1',
          relativePath: 'packages/app/lib/main.dart',
          area: GitChangeArea.unstaged,
          scope: WorkspaceGitDiffScope.file,
          gitDiffRoot: 'packages/app',
        );
        final first = await service.openOrCreateGitCommitDiffTab(
          workspaceId: 'workspace-1',
          relativePath: './packages\\app\\lib\\main.dart',
          oldPath: './packages\\app\\lib\\old_main.dart',
          scope: WorkspaceGitDiffScope.file,
          gitDiffRoot: './packages\\app',
          commitOid: 'abc123456789',
          parentOid: 'def987654321',
          compareRef: 'abc1234',
          subject: 'Add Main',
          message: 'Add Main\n\nBody',
        );
        final second = await service.openOrCreateGitCommitDiffTab(
          workspaceId: 'workspace-1',
          relativePath: 'packages/app/lib/main.dart',
          oldPath: 'packages/app/lib/old_main.dart',
          scope: WorkspaceGitDiffScope.file,
          gitDiffRoot: 'packages/app',
          commitOid: 'abc123456789',
          parentOid: 'def987654321',
          compareRef: 'abc1234',
        );

        expect(first.id, isNot(workingTreeTab.id));
        expect(second.id, first.id);
        expect(first.kind, WorkspaceTabKind.gitDiff);
        expect(first.title, 'main.dart abc1234');
        expect(first.gitDiffSource, WorkspaceGitDiffSource.commit);
        expect(first.gitDiffScope, WorkspaceGitDiffScope.file);
        expect(first.filePath, 'packages/app/lib/main.dart');
        expect(first.gitDiffOldPath, 'packages/app/lib/old_main.dart');
        expect(first.gitDiffRoot, 'packages/app');
        expect(first.gitDiffCommitOid, 'abc123456789');
        expect(first.gitDiffParentOid, 'def987654321');
        expect(first.gitDiffCompareRef, 'abc1234');
        expect(first.gitDiffCommitSubject, 'Add Main');
        expect(first.gitDiffCommitMessage, 'Add Main\n\nBody');
        expect(repository.tabs, hasLength(2));
      },
    );

    test(
      'openOrCreateGitPullRequestDiffTab stores and reuses the PR range',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 8, 10),
        );

        final first = await service.openOrCreateGitPullRequestDiffTab(
          workspaceId: 'workspace-1',
          pullRequestNumber: 385,
          commitOid: 'head123',
          parentOid: 'base123',
          subject: 'feat: subscription-backed reading diffs',
        );
        final second = await service.openOrCreateGitPullRequestDiffTab(
          workspaceId: 'workspace-1',
          pullRequestNumber: 385,
          commitOid: 'head123',
          parentOid: 'base123',
        );
        final retargeted = await service.openOrCreateGitPullRequestDiffTab(
          workspaceId: 'workspace-1',
          pullRequestNumber: 385,
          commitOid: 'head123',
          parentOid: 'new-base456',
        );

        expect(second.id, first.id);
        expect(retargeted.id, isNot(first.id));
        expect(first.title, 'Pull request #385');
        expect(first.gitDiffSource, WorkspaceGitDiffSource.pullRequest);
        expect(first.gitDiffScope, WorkspaceGitDiffScope.all);
        expect(first.gitDiffPullRequestNumber, 385);
        expect(first.gitDiffCommitOid, 'head123');
        expect(first.gitDiffParentOid, 'base123');
        expect(
          first.gitDiffCommitSubject,
          'feat: subscription-backed reading diffs',
        );
        expect(repository.tabs, hasLength(2));
      },
    );

    test('updates git diff roots after a folder move', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.gitDiff,
            title: 'app changes',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabGitDiffScopePayloadKey: 'all',
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

      expect(result.updatedTabs.single.gitDiffRoot, 'modules/app');
      expect(repository.tabs.single.gitDiffRoot, 'modules/app');
      expect(repository.tabs.single.title, 'app changes');
    });

    test('does not retarget commit diff tabs after a folder move', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.addAll(<WorkspaceTabRecord>[
          WorkspaceTabRecord(
            id: 'working-tree-tab',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.gitDiff,
            title: 'app changes',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabGitDiffScopePayloadKey: 'all',
              workspaceTabGitDiffRootPayloadKey: 'packages/app',
            },
          ),
          WorkspaceTabRecord(
            id: 'commit-tab',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.gitDiff,
            title: 'main.dart abc1234',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabGitDiffSourcePayloadKey: 'commit',
              workspaceTabFilePathPayloadKey: 'packages/app/lib/main.dart',
              workspaceTabGitDiffOldPathPayloadKey:
                  'packages/app/lib/old_main.dart',
              workspaceTabGitDiffScopePayloadKey: 'file',
              workspaceTabGitDiffRootPayloadKey: 'packages/app',
              workspaceTabGitDiffCommitOidPayloadKey: 'abc123456789',
              workspaceTabGitDiffParentOidPayloadKey: 'def987654321',
              workspaceTabGitDiffCompareRefPayloadKey: 'abc1234',
            },
          ),
        ]);
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final result = await service.updateFileTabPathsAfterMove(
        workspaceId: 'workspace-1',
        oldRelativePath: 'packages',
        newRelativePath: 'modules',
      );

      expect(result.updatedTabs.single.id, 'working-tree-tab');
      expect(repository.tabs[0].gitDiffRoot, 'modules/app');
      expect(repository.tabs[1].filePath, 'packages/app/lib/main.dart');
      expect(
        repository.tabs[1].gitDiffOldPath,
        'packages/app/lib/old_main.dart',
      );
      expect(repository.tabs[1].gitDiffRoot, 'packages/app');
    });

    test('updates git diff roots and file paths after a folder move', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: WorkspaceTabKind.gitDiff,
            title: 'main.dart unstaged',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
            payload: const <String, Object?>{
              workspaceTabFilePathPayloadKey: 'packages/app/lib/main.dart',
              workspaceTabGitDiffScopePayloadKey: 'file',
              workspaceTabGitDiffAreaPayloadKey: 'unstaged',
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
  Future<Workspace> setWorkspacePinned(
    String workspaceId,
    bool isPinned,
  ) async => throw StateError('Workspace not found');

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) =>
      const Stream<List<WorkspaceTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}
