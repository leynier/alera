part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerSessionCacheTests() {
  testWidgets(
    'keeps expanded folders after leaving and returning to Explorer',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
          _file('readme.md'),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ];
      final harnessKey = GlobalKey<_ExplorerVisibilityHarnessState>();

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: _ExplorerVisibilityHarness(
                  key: harnessKey,
                  workspace: _workspace(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      harnessKey.currentState!.hideExplorer();
      await tester.pumpAndSettle();
      expect(find.text('src'), findsNothing);

      harnessKey.currentState!.showExplorer();
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);
    },
  );

  testWidgets('keeps scroll offset after leaving and returning to Explorer', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        for (var i = 0; i < 40; i++) _file('file-$i.dart'),
      ];
    final harnessKey = GlobalKey<_ExplorerVisibilityHarnessState>();

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: _ExplorerVisibilityHarness(
                key: harnessKey,
                workspace: _workspace(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    );
    expect(listFinder, findsOneWidget);
    await tester.drag(listFinder, const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = tester.state<ScrollableState>(listFinder).position.pixels;
    expect(scrolled, greaterThan(50));

    harnessKey.currentState!.hideExplorer();
    await tester.pumpAndSettle();
    expect(listFinder, findsNothing);

    harnessKey.currentState!.showExplorer();
    await tester.pumpAndSettle();
    final restored = tester.state<ScrollableState>(listFinder).position.pixels;
    expect(restored, closeTo(scrolled, 1));
  });
}
