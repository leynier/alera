part of 'workspace_git_diff_panel_test.dart';

void _registerWorkspaceGitDiffPanelPreviewTests() {
  testWidgets('tapping a changed file opens a preview diff tab', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final opened = <({String? relativePath, bool preview})>[];

    await _pumpPanel(
      tester,
      backend: backend,
      onOpenGitDiff:
          ({
            area,
            relativePath,
            gitDiffRoot,
            required scope,
            bool preview = false,
          }) async {
            opened.add((relativePath: relativePath, preview: preview));
          },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('lib/foo.dart'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.relativePath, 'lib/foo.dart');
    expect(opened.single.preview, isTrue);

    await tester.tap(find.text('lib/foo.dart'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(3));
    expect(opened[1].preview, isTrue);
    expect(opened[2].preview, isFalse);
    expect(opened.map((open) => open.relativePath).toSet(), <String>{
      'lib/foo.dart',
    });
  });

  testWidgets('all changes stays a permanent diff tab', (tester) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final opened = <({WorkspaceGitDiffScope scope, bool preview})>[];

    await _pumpPanel(
      tester,
      backend: backend,
      onOpenGitDiff:
          ({
            area,
            relativePath,
            gitDiffRoot,
            required scope,
            bool preview = false,
          }) async {
            opened.add((scope: scope, preview: preview));
          },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('All Changes'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.scope, WorkspaceGitDiffScope.all);
    expect(opened.single.preview, isFalse);
  });

  testWidgets('commits panel loads history and opens commit file diffs', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
      )
      ..gitHistoryResult = GitHistoryResult(
        currentRef: const GitHistoryItemRef(
          id: 'refs/heads/main',
          name: 'main',
          revision: 'abc123456789',
        ),
        hasIncomingChanges: false,
        hasOutgoingChanges: false,
        hasMore: false,
        limit: 50,
        items: <GitHistoryItem>[
          GitHistoryItem(
            id: 'abc123456789',
            parentIds: const <String>['def987654321'],
            subject: 'Add Feature',
            message: 'Add Feature\n\nBody',
            displayId: 'abc1234',
            author: 'Leynier',
            timestamp: DateTime.utc(2026, 7, 4, 12),
          ),
        ],
      )
      ..gitCommitCompareResult = const GitCommitCompareResult(
        summary: GitCommitCompareSummary(
          commitOid: 'abc123456789',
          parentOid: 'def987654321',
          compareRef: 'abc1234',
          baseRef: 'def9876',
          changedFiles: 1,
          status: GitCommitCompareStatus.ready,
        ),
        entries: <GitCommitChangeEntry>[
          GitCommitChangeEntry(
            path: 'lib/new.dart',
            oldPath: 'lib/old.dart',
            status: GitChangeStatus.renamed,
            added: 3,
            removed: 1,
          ),
        ],
      );
    final opened =
        <
          ({
            String? relativePath,
            String? oldPath,
            WorkspaceGitDiffScope scope,
            String? gitDiffRoot,
            String commitOid,
            String? parentOid,
            String compareRef,
            String? subject,
            String? message,
            bool preview,
          })
        >[];

    await _pumpPanel(
      tester,
      backend: backend,
      onOpenGitCommitDiff:
          ({
            relativePath,
            oldPath,
            required scope,
            gitDiffRoot,
            required commitOid,
            parentOid,
            required compareRef,
            subject,
            message,
            bool preview = false,
          }) async {
            opened.add((
              relativePath: relativePath,
              oldPath: oldPath,
              scope: scope,
              gitDiffRoot: gitDiffRoot,
              commitOid: commitOid,
              parentOid: parentOid,
              compareRef: compareRef,
              subject: subject,
              message: message,
              preview: preview,
            ));
          },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('COMMITS'));
    await tester.pumpAndSettle();

    expect(find.text('Add Feature'), findsOneWidget);
    expect(
      backend.calls.where((call) => call.method == 'history').single.args,
      <String, Object?>{'path': '/tmp/project', 'limit': 50, 'baseRef': null},
    );

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(find.text('Add Feature')),
    );
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    await tester.tap(find.text('Add Feature'));
    await tester.pumpAndSettle();

    expect(find.textContaining('lib/old.dart -> lib/new.dart'), findsOneWidget);
    expect(
      backend.calls.where((call) => call.method == 'commitCompare').single.args,
      <String, Object?>{'path': '/tmp/project', 'commitId': 'abc123456789'},
    );

    await mouse.moveTo(
      tester.getCenter(find.textContaining('lib/old.dart -> lib/new.dart')),
    );
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    await tester.tap(find.textContaining('lib/old.dart -> lib/new.dart'));
    await tester.pumpAndSettle();

    expect(opened.single.relativePath, 'lib/new.dart');
    expect(opened.single.oldPath, 'lib/old.dart');
    expect(opened.single.scope, WorkspaceGitDiffScope.file);
    expect(opened.single.gitDiffRoot, isNull);
    expect(opened.single.commitOid, 'abc123456789');
    expect(opened.single.parentOid, 'def987654321');
    expect(opened.single.compareRef, 'abc1234');
    expect(opened.single.subject, 'Add Feature');
    expect(opened.single.message, 'Add Feature\n\nBody');
    expect(opened.single.preview, isTrue);
  });
}
