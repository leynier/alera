part of 'workspace_git_diff_surface_test.dart';

void _registerWorkspaceGitDiffSurfacePullRequestTests() {
  testWidgets('diff surface loads linked pull request ranges as commit diffs', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitCommitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .staged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            sourceLabel: 'Commit',
          ),
        ],
      );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(
        source: .pullRequest,
        filePath: null,
        title: 'Pull request #385',
        scope: .all,
        area: null,
        commitOid: 'head123',
        parentOid: 'base123',
        compareRef: '#385',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'commitDiff').single.args,
      <String, Object?>{
        'path': '/tmp/project',
        'commitOid': 'head123',
        'parentOid': 'base123',
        'filePath': null,
        'oldPath': null,
      },
    );
    expect(find.byTooltip('Generate Reading Diff'), findsOneWidget);
    expect(find.text('Pull Request · lib/main.dart'), findsOneWidget);
  });
}
