part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerRevealTests() {
  testWidgets('queued reveal expands ancestors and selects the file', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('src', hasChildrenHint: true),
      ]
      ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
        _file('src/main.dart'),
      ];
    late ProviderContainer container;
    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return WorkspaceExplorer(
                    workspace: _workspace(),
                    mode: WorkspaceExplorerMode.hideIgnored,
                    onModeChanged: (_) {},
                    onOpenFile: (_) {},
                    onPathMoved: (_, _) async {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);

    container
        .read(workspaceExplorerRevealControllerProvider.notifier)
        .reveal(workspaceId: 'workspace-1', relativePath: 'src/main.dart');
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(container.read(workspaceExplorerRevealControllerProvider), isNull);
  });
}
