import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

part 'workspace_tab_path_moves_test_cases.dart';
part 'workspace_tab_git_preview_test_cases.dart';

void main() {
  group('WorkspaceTabService', () {
    _registerWorkspaceTabPathMoveTests();
    _registerWorkspaceTabGitPreviewTests();

    test('ensureInitialTerminalTab creates the first terminal workspace tab when none exist', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21),
      );
      final tab = await service.ensureInitialTerminalTab('workspace-1');
      expect(tab.title, 'Terminal 1');
      expect(tab.terminalSessionId, tab.id);
      expect(repository.tabs.single.title, 'Terminal 1');
    });

    test(
      'createTerminalTab picks the next available terminal ordinal',
      () async {
        final repository = _FakeWorkbenchRepository()
          ..tabs.addAll(<WorkspaceTabRecord>[
            WorkspaceTabRecord(
              id: 'tab-1',
              workspaceId: 'workspace-1',
              title: 'Terminal 1',
              createdAt: .utc(2026, 5, 21),
              updatedAt: .utc(2026, 5, 21),
            ),
            WorkspaceTabRecord(
              id: 'tab-3',
              workspaceId: 'workspace-1',
              title: 'Terminal 3',
              createdAt: .utc(2026, 5, 21),
              updatedAt: .utc(2026, 5, 21),
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
            kind: .editor,
            title: 'diagram.mmd preview',
            createdAt: .utc(2026, 5, 21),
            updatedAt: .utc(2026, 5, 21),
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
            kind: .editor,
            title: 'guide.pdf',
            createdAt: .utc(2026, 5, 21),
            updatedAt: .utc(2026, 5, 21),
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
            kind: .pdf,
            title: 'guide.pdf',
            createdAt: .utc(2026, 5, 21),
            updatedAt: .utc(2026, 5, 21),
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
        area: .unstaged,
        scope: .file,
      );
      final second = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/main.dart',
        area: .unstaged,
        scope: .file,
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
        scope: .all,
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
        scope: .all,
        gitDiffRoot: './packages\\app',
      );
      final workspaceTab = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: .all,
      );
      final rootAgain = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        scope: .all,
        gitDiffRoot: 'packages/app',
      );

      expect(rootTab.title, 'app changes');
      expect(rootTab.gitDiffRoot, 'packages/app');
      expect(workspaceTab.gitDiffRoot, isNull);
      expect(rootAgain.id, rootTab.id);
      expect(repository.tabs, hasLength(2));
    });

    test('openOrCreateGitCommitDiffTab creates and reuses commit diff tabs independently', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final workingTreeTab = await service.openOrCreateGitDiffTab(
        workspaceId: 'workspace-1',
        relativePath: 'packages/app/lib/main.dart',
        area: .unstaged,
        scope: .file,
        gitDiffRoot: 'packages/app',
      );
      final first = await service.openOrCreateGitCommitDiffTab(
        workspaceId: 'workspace-1',
        relativePath: './packages\\app\\lib\\main.dart',
        oldPath: './packages\\app\\lib\\old_main.dart',
        scope: .file,
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
        scope: .file,
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
    });

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
          retentionId: 'retention-1',
          subject: 'feat: subscription-backed reading diffs',
        );
        final second = await service.openOrCreateGitPullRequestDiffTab(
          workspaceId: 'workspace-1',
          pullRequestNumber: 385,
          commitOid: 'head123',
          parentOid: 'base123',
          retentionId: 'retention-2',
        );
        final retargeted = await service.openOrCreateGitPullRequestDiffTab(
          workspaceId: 'workspace-1',
          pullRequestNumber: 385,
          commitOid: 'head123',
          parentOid: 'new-base456',
          retentionId: 'retention-3',
        );

        expect(second.id, first.id);
        expect(retargeted.id, isNot(first.id));
        expect(first.title, 'Pull request #385');
        expect(first.gitDiffSource, WorkspaceGitDiffSource.pullRequest);
        expect(first.gitDiffScope, WorkspaceGitDiffScope.all);
        expect(first.gitDiffPullRequestNumber, 385);
        expect(first.gitDiffCommitOid, 'head123');
        expect(first.gitDiffParentOid, 'base123');
        expect(first.gitDiffHostedReviewRetentionId, 'retention-1');
        expect(retargeted.gitDiffHostedReviewRetentionId, 'retention-3');
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
            kind: .gitDiff,
            title: 'app changes',
            createdAt: .utc(2026, 5, 21),
            updatedAt: .utc(2026, 5, 21),
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

    test(
      'updates commit-backed roots without retargeting historical file paths',
      () async {
        final repository = _FakeWorkbenchRepository()
          ..tabs.addAll(<WorkspaceTabRecord>[
            WorkspaceTabRecord(
              id: 'working-tree-tab',
              workspaceId: 'workspace-1',
              kind: .gitDiff,
              title: 'app changes',
              createdAt: .utc(2026, 5, 21),
              updatedAt: .utc(2026, 5, 21),
              payload: const <String, Object?>{
                workspaceTabGitDiffScopePayloadKey: 'all',
                workspaceTabGitDiffRootPayloadKey: 'packages/app',
              },
            ),
            WorkspaceTabRecord(
              id: 'commit-tab',
              workspaceId: 'workspace-1',
              kind: .gitDiff,
              title: 'main.dart abc1234',
              createdAt: .utc(2026, 5, 21),
              updatedAt: .utc(2026, 5, 21),
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
            WorkspaceTabRecord(
              id: 'pull-request-tab',
              workspaceId: 'workspace-1',
              kind: .gitDiff,
              title: 'Pull request #385',
              createdAt: .utc(2026, 5, 21),
              updatedAt: .utc(2026, 5, 21),
              payload: const <String, Object?>{
                workspaceTabGitDiffSourcePayloadKey: 'pullRequest',
                workspaceTabGitDiffScopePayloadKey: 'all',
                workspaceTabGitDiffRootPayloadKey: 'packages/app',
                workspaceTabGitDiffCommitOidPayloadKey: 'head123',
                workspaceTabGitDiffParentOidPayloadKey: 'base123',
                workspaceTabGitDiffPullRequestNumberPayloadKey: 385,
                workspaceTabGitDiffHostedReviewRetentionIdPayloadKey:
                    '0123456789abcdef0123456789abcdef',
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

        expect(
          result.updatedTabs.map((tab) => tab.id),
          containsAll(<String>[
            'working-tree-tab',
            'commit-tab',
            'pull-request-tab',
          ]),
        );
        expect(repository.tabs[0].gitDiffRoot, 'modules/app');
        expect(repository.tabs[1].filePath, 'packages/app/lib/main.dart');
        expect(
          repository.tabs[1].gitDiffOldPath,
          'packages/app/lib/old_main.dart',
        );
        expect(repository.tabs[1].gitDiffRoot, 'modules/app');
        expect(repository.tabs[2].title, 'Pull request #385');
        expect(repository.tabs[2].gitDiffRoot, 'modules/app');
        expect(repository.tabs[2].gitDiffCommitOid, 'head123');
      },
    );

    test('updates git diff roots and file paths after a folder move', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.add(
          WorkspaceTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            kind: .gitDiff,
            title: 'main.dart unstaged',
            createdAt: .utc(2026, 5, 21),
            updatedAt: .utc(2026, 5, 21),
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
          scope: .file,
        ),
        throwsStateError,
      );
      await expectLater(
        service.openOrCreateGitDiffTab(
          workspaceId: 'workspace-1',
          area: .staged,
          scope: .file,
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
            createdAt: .utc(2026, 5, 21),
            updatedAt: .utc(2026, 5, 21),
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

    test('openOrCreateEditorTab marks a preview tab in payload', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final tab = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/main.dart',
        preview: true,
      );

      expect(tab.kind, WorkspaceTabKind.editor);
      expect(tab.filePath, 'lib/main.dart');
      expect(tab.isPreview, isTrue);
      expect(tab.isFilePreviewSlot, isTrue);
      expect(tab.payload[workspaceTabPreviewPayloadKey], isTrue);
      expect(repository.tabs.single.isPreview, isTrue);
    });

    test('preview open retargets the replaceable file preview tab', () async {
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
      final second = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/b.dart',
        preview: true,
        replacePreviewTabId: first.id,
      );

      expect(second.id, first.id);
      expect(second.filePath, 'lib/b.dart');
      expect(second.title, 'b.dart');
      expect(second.isPreview, isTrue);
      expect(repository.tabs, hasLength(1));
    });

    test('keepPreviewTab removes the preview payload key', () async {
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
      final kept = await service.keepPreviewTab(preview.id);

      expect(kept.id, preview.id);
      expect(kept.isPreview, isFalse);
      expect(kept.payload.containsKey(workspaceTabPreviewPayloadKey), isFalse);
      expect(repository.tabs.single.isPreview, isFalse);
    });

    test('keepPreviewTab is a no-op for permanent tabs', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final tab = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/a.dart',
      );
      final kept = await service.keepPreviewTab(tab.id);

      expect(kept.id, tab.id);
      expect(kept.isPreview, isFalse);
      expect(repository.tabs, hasLength(1));
    });

    test('keepPreviewTab rejects a missing tab', () async {
      final service = WorkspaceTabService(
        repository: _FakeWorkbenchRepository(),
      );

      await expectLater(
        service.keepPreviewTab('missing-tab'),
        throwsStateError,
      );
    });

    test('permanent open does not steal another file preview tab', () async {
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
      final permanent = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/b.dart',
        replacePreviewTabId: preview.id,
      );

      expect(permanent.id, isNot(preview.id));
      expect(permanent.isPreview, isFalse);
      expect(permanent.filePath, 'lib/b.dart');
      expect(repository.tabs, hasLength(2));
      expect(
        repository.tabs.singleWhere((tab) => tab.id == preview.id).isPreview,
        isTrue,
      );
    });

    test('reopening the same preview path reuses the tab', () async {
      final repository = _FakeWorkbenchRepository();
      final service = WorkspaceTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final first = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: './lib/a.dart',
        preview: true,
      );
      final second = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/a.dart',
        preview: true,
      );

      expect(second.id, first.id);
      expect(second.isPreview, isTrue);
      expect(repository.tabs, hasLength(1));
    });

    test(
      'replacePreviewTabId is ignored for non-preview and merman tabs',
      () async {
        final repository = _FakeWorkbenchRepository();
        final service = WorkspaceTabService(
          repository: repository,
          now: () => DateTime.utc(2026, 5, 21, 1),
        );
        final terminal = await service.ensureInitialTerminalTab('workspace-1');
        final merman = await service.openOrCreateMermanPreviewTab(
          workspaceId: 'workspace-1',
          relativePath: 'docs/diagram.mmd',
        );

        final fromTerminal = await service.openOrCreateEditorTab(
          workspaceId: 'workspace-1',
          relativePath: 'lib/a.dart',
          preview: true,
          replacePreviewTabId: terminal.id,
        );
        final fromMerman = await service.openOrCreateEditorTab(
          workspaceId: 'workspace-1',
          relativePath: 'lib/b.dart',
          preview: true,
          replacePreviewTabId: merman.id,
        );

        expect(fromTerminal.id, isNot(terminal.id));
        expect(fromMerman.id, isNot(merman.id));
        expect(fromMerman.id, isNot(fromTerminal.id));
        expect(repository.tabs, hasLength(4));
      },
    );

    test('permanent open of a preview path pins that tab', () async {
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
      final pinned = await service.openOrCreateEditorTab(
        workspaceId: 'workspace-1',
        relativePath: 'lib/a.dart',
      );

      expect(pinned.id, preview.id);
      expect(pinned.isPreview, isFalse);
      expect(repository.tabs, hasLength(1));
      expect(repository.tabs.single.isPreview, isFalse);
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
  Future<WorkspaceTabRecord> upsertWorkspaceTab(
    WorkspaceTabRecord tab, {
    bool manualRename = false,
  }) async {
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
