part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerGitSnapshotTests() {
  testWidgets('rows show git status indicators', (tester) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('added.dart', gitStatus: native.WorkspaceFileGitStatus.added),
        _file(
          'modified.dart',
          gitStatus: native.WorkspaceFileGitStatus.modified,
        ),
        _file(
          'untracked.dart',
          gitStatus: native.WorkspaceFileGitStatus.untracked,
        ),
      ];

    await _pumpExplorer(tester, service);

    expect(find.text('A'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('U'), findsOneWidget);
  });

  testWidgets('reuses one Git snapshot across expanded directories', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('src', hasChildrenHint: true),
      ]
      ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
        _file('src/main.dart'),
      ];
    final gitBackend = FakeGitBackend();

    await _pumpExplorer(tester, service, gitBackend: gitBackend);
    expect(
      gitBackend.calls.where((call) => call.method == 'explorerStatusSnapshot'),
      hasLength(1),
    );

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    expect(
      gitBackend.calls.where((call) => call.method == 'explorerStatusSnapshot'),
      hasLength(1),
    );

    service.emitWatchBatch(<String>['', 'src']);
    await tester.pumpAndSettle();

    expect(
      gitBackend.calls.where((call) => call.method == 'explorerStatusSnapshot'),
      hasLength(2),
    );
  });
}
