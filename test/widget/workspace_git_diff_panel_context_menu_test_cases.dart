part of 'workspace_git_diff_panel_test.dart';

void _registerWorkspaceGitDiffPanelContextMenuTests() {
  testWidgets('tree file context menu opens the file instead of the diff', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/src/dirty.dart',
            area: .unstaged,
            status: .modified,
          ),
        ],
      );
    final opened = <String>[];

    await _pumpPanel(
      tester,
      backend: backend,
      viewMode: .tree,
      onOpenFile: opened.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('dirty.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Open File'), findsOneWidget);
    expect(find.text('Reveal in Explorer'), findsOneWidget);
    expect(find.text('Stage'), findsWidgets);
    expect(find.text('Discard'), findsWidgets);

    await tester.tap(find.text('Open File'));
    await tester.pumpAndSettle();

    expect(opened, <String>['lib/src/dirty.dart']);
  });

  testWidgets(
    'file context menu comments on the diff and shows the draft bar',
    (tester) async {
      final backend = FakeGitBackend()
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/src/dirty.dart',
              area: .unstaged,
              status: .modified,
            ),
          ],
        );

      await _pumpPanel(tester, backend: backend, viewMode: .flat);
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('lib/src/dirty.dart'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Comment on Diff'), findsOneWidget);

      await tester.tap(find.text('Comment on Diff'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'This change looks wrong.',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add Comment'));
      await tester.pumpAndSettle();

      expect(find.text('1 Comment'), findsOneWidget);
      expect(find.text('lib/src/dirty.dart · (Unstaged)'), findsOneWidget);
      expect(find.text('This change looks wrong.'), findsOneWidget);
    },
  );

  testWidgets('tree folder context menu stages the folder path', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/src/dirty.dart',
            area: .unstaged,
            status: .modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend, viewMode: .tree);
    await tester.pumpAndSettle();

    await tester.tap(find.text('src'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Open File'), findsNothing);
    expect(find.text('Reveal in Explorer'), findsOneWidget);

    await tester.tap(find.text('Stage').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'stageArea').single.args,
      <String, Object?>{
        'path': '/tmp/project',
        'area': GitChangeArea.unstaged,
        'filePath': 'lib/src',
      },
    );
  });

  testWidgets('tree file context menu reveals the workspace-relative path', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/src/dirty.dart',
            area: .unstaged,
            status: .modified,
          ),
        ],
      );
    final revealed = <String>[];

    await _pumpPanel(
      tester,
      backend: backend,
      viewMode: .tree,
      sourceControlScope: const WorkspaceSourceControlScope(
        workspaceId: 'workspace-1',
        workspacePath: '/tmp/project',
        path: '/tmp/project/packages/app',
        relativeRoot: 'packages/app',
      ),
      onRevealInExplorer: revealed.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('dirty.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal in Explorer'));
    await tester.pumpAndSettle();

    expect(revealed, <String>['packages/app/lib/src/dirty.dart']);
  });
}
