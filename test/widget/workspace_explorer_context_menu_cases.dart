part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerContextMenuTests() {
  testWidgets('background context menu creates items at workspace root', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService();
    await _pumpExplorer(tester, service);

    await tester.tapAt(const Offset(250, 220), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'root.txt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(service.createdFiles, <String>['root.txt']);
  });

  testWidgets('context menu comments on a file and shows the draft bar', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    await _pumpExplorer(tester, service);

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comment on File'));
    await tester.pumpAndSettle();

    expect(find.text('Comment on File'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'Explain this file.');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Comment'));
    await tester.pumpAndSettle();

    expect(find.text('1 Comment'), findsOneWidget);
    expect(find.text('Send to Agent'), findsOneWidget);
    expect(find.text('Explain this file.'), findsOneWidget);
  });

  testWidgets('context menu copies relative paths and duplicates entries', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    await _pumpExplorer(tester, service);

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy relative path'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copiedText, 'readme.md');

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.copiedFiles, <String>['readme.md->']);
  });

  testWidgets('context menu reveals entries in the file manager', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    final opener = _FakeWorkspaceFolderOpener();
    await _pumpExplorer(tester, service, folderOpener: opener);

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal in Finder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opener.revealedPaths, <String>[p.join('/repo/alera', 'readme.md')]);
  });

  testWidgets('context menu focuses and clears source control root', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('packages', hasChildrenHint: true),
      ]
      ..childrenByDirectory['packages'] = <native.WorkspaceFileEntry>[
        _directory('packages/app', hasChildrenHint: false),
      ];
    final focused = <String>[];
    var cleared = false;

    await _pumpExplorer(
      tester,
      service,
      onFocusSourceControlFolder: (relativePath) async {
        focused.add(relativePath);
        return true;
      },
      onClearSourceControlRoot: () => cleared = true,
    );

    if (find.text('app').evaluate().isEmpty) {
      await tester.tap(find.text('packages'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('app'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use As Source Control Root'));
    await tester.pumpAndSettle();

    expect(focused, <String>['packages/app']);

    await _pumpExplorer(
      tester,
      service,
      focusedSourceControlRoot: 'packages/app',
      onFocusSourceControlFolder: (relativePath) async {
        focused.add(relativePath);
        return true;
      },
      onClearSourceControlRoot: () => cleared = true,
    );
    if (find.text('app').evaluate().isEmpty) {
      await tester.tap(find.text('packages'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('app'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Source Control Root'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
  });

  testWidgets(
    'context menu hides source control root action without callback',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('packages', hasChildrenHint: true),
        ]
        ..childrenByDirectory['packages'] = <native.WorkspaceFileEntry>[
          _directory('packages/app', hasChildrenHint: false),
        ];

      await _pumpExplorer(tester, service);

      if (find.text('app').evaluate().isEmpty) {
        await tester.tap(find.text('packages'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('app'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Use As Source Control Root'), findsNothing);
      expect(find.text('Clear Source Control Root'), findsNothing);
    },
  );

  testWidgets('creating a file does not use disposed state after unmount', (
    tester,
  ) async {
    final createGate = Completer<void>();
    final service = _FakeWorkspaceFileService(createGate: createGate);

    await _pumpExplorer(tester, service);
    await tester.tap(find.byTooltip('New file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'created.dart');
    await tester.tap(find.text('Create'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    createGate.complete();
    await tester.pumpAndSettle();

    expect(service.createdFiles, <String>['created.dart']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('context sidebar uses rail only while collapsed', (tester) async {
    final service = _FakeWorkspaceFileService();

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceContextSidebar(
              workspace: _workspace(),
              prefs: WorkbenchViewPrefs.defaults.copyWith(
                rightSidebarVisible: false,
              ),
              onToggleVisible: () {},
              onResize: (_) {},
              onSetContextPanelTab: (_) {},
              onSetExplorerMode: (_) {},
              onSetGitDiffViewMode: (_) {},
              onSetGitDiffGroupMode: (_) {},
              onOpenFile: (_) {},
              onOpenGitDiff: ({
                relativePath,
                area,
                gitDiffRoot,
                required scope,
                bool preview = false,
                bool oppositePanel = false,
              }) async {},
              onOpenGitCommitDiff: ({
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
                bool oppositePanel = false,
              }) async {},
              onOpenSearchMatch: (_) {},
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Expand panel'), findsOneWidget);
    expect(find.byTooltip('Explorer'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Source Control'), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(
      tester.getTopLeft(find.byTooltip('Explorer')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('Search')).dy),
    );
    expect(
      tester.getTopLeft(find.byTooltip('Search')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('Source Control')).dy),
    );
    expect(find.byType(WorkspaceExplorer), findsNothing);

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceContextSidebar(
              workspace: _workspace(),
              prefs: .defaults,
              onToggleVisible: () {},
              onResize: (_) {},
              onSetContextPanelTab: (_) {},
              onSetExplorerMode: (_) {},
              onSetGitDiffViewMode: (_) {},
              onSetGitDiffGroupMode: (_) {},
              onOpenFile: (_) {},
              onOpenGitDiff: ({
                relativePath,
                area,
                gitDiffRoot,
                required scope,
                bool preview = false,
                bool oppositePanel = false,
              }) async {},
              onOpenGitCommitDiff: ({
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
                bool oppositePanel = false,
              }) async {},
              onOpenSearchMatch: (_) {},
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand panel'), findsNothing);
    expect(find.byTooltip('Collapse panel'), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(find.byType(WorkspaceExplorer), findsOneWidget);
  });
}
