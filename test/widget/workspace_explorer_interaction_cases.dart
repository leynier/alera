part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerInteractionTests() {
  testWidgets('single click toggles folders and rows expose click cursors', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('src', hasChildrenHint: true),
        _file('readme.md'),
      ]
      ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
        _file('src/main.dart'),
      ];
    final opened = <String>[];

    await _pumpExplorer(tester, service, onOpenFile: opened.add);

    expect(find.text('src'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(
      find.ancestor(
        of: find.text('src'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.text('readme.md'));
    await tester.pumpAndSettle();
    expect(opened, <String>['readme.md']);
  });

  testWidgets('second tap on the same file keeps it open', (tester) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    final opened = <String>[];
    final kept = <String>[];

    await _pumpExplorer(
      tester,
      service,
      onOpenFile: opened.add,
      onOpenFilePermanently: kept.add,
    );

    await tester.tap(find.text('readme.md'));
    await tester.pump();
    await tester.tap(find.text('readme.md'));
    await tester.pump();

    expect(opened, <String>['readme.md', 'readme.md']);
    expect(kept, <String>['readme.md']);
  });

  testWidgets(
    'refresh prunes stale expanded children after a folder disappears',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ];

      await _pumpExplorer(tester, service);
      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      service.childrenByDirectory[''] = const <native.WorkspaceFileEntry>[];
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('src'), findsNothing);
      expect(find.text('main.dart'), findsNothing);
    },
  );

  testWidgets('native watcher refreshes loaded directories after changes', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];

    await _pumpExplorer(tester, service);
    expect(find.text('external.dart'), findsNothing);

    service.childrenByDirectory[''] = <native.WorkspaceFileEntry>[
      _file('external.dart'),
      _file('readme.md'),
    ];
    service.emitWatchBatch(<String>['']);
    await tester.pumpAndSettle();

    expect(find.text('external.dart'), findsOneWidget);
    expect(service.watchedPathUpdates.last, contains(''));
  });

  testWidgets(
    'context sidebar loads the next workspace explorer without manual refresh',
    (tester) async {
      final stopGate = Completer<void>();
      final service = _FakeWorkspaceFileService(stopGate: stopGate)
        ..childrenByWorkspacePath['/repo/alera'] =
            <String, List<native.WorkspaceFileEntry>>{
              '': <native.WorkspaceFileEntry>[_file('main.dart')],
            }
        ..childrenByWorkspacePath['/repo/alera-feature'] =
            <String, List<native.WorkspaceFileEntry>>{
              '': <native.WorkspaceFileEntry>[_file('feature.dart')],
            };

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: _workspaceContextSidebar(_workspace()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('feature.dart'), findsNothing);

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: _workspaceContextSidebar(
                  _workspace(
                    id: 'workspace-2',
                    name: 'Feature',
                    path: '/repo/alera-feature',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('main.dart'), findsNothing);
      expect(find.text('feature.dart'), findsOneWidget);

      stopGate.complete();
    },
  );

  testWidgets(
    'ignored files toggle refreshes the listing without manual refresh',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _file('tracked.dart'),
        ]
        ..showAllChildrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _file('ignored.dart'),
          _file('tracked.dart'),
        ];

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: const _WorkspaceExplorerModeHarness(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('tracked.dart'), findsOneWidget);
      expect(find.text('ignored.dart'), findsNothing);
      expect(service.listChildrenCalls.last.hideIgnored, isTrue);

      await tester.tap(find.byTooltip('Show ignored files'));
      await tester.pumpAndSettle();

      expect(find.text('tracked.dart'), findsOneWidget);
      expect(find.text('ignored.dart'), findsOneWidget);
      expect(
        service.listChildrenCalls.map((call) => call.hideIgnored),
        containsAllInOrder(<bool>[true, false]),
      );
    },
  );

  testWidgets(
    'ignored files toggle reloads expanded directories with the new filter',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ]
        ..showAllChildrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..showAllChildrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/generated.dart'),
          _file('src/main.dart'),
        ];

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: const _WorkspaceExplorerModeHarness(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('generated.dart'), findsNothing);

      await tester.tap(find.byTooltip('Show ignored files'));
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('generated.dart'), findsOneWidget);
      expect(
        service.listChildrenCalls,
        contains(
          const _ListChildrenCall(relativePath: 'src', hideIgnored: false),
        ),
      );
    },
  );

  testWidgets('ignored files toggle clears stale rows when root reload fails', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('tracked.dart'),
      ]
      ..failingListChildrenCalls.add(
        const _ListChildrenCall(relativePath: '', hideIgnored: false),
      );

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: const _WorkspaceExplorerModeHarness(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('tracked.dart'), findsOneWidget);

    await tester.tap(find.byTooltip('Show ignored files'));
    await tester.pumpAndSettle();

    expect(find.text('tracked.dart'), findsNothing);
  });

  testWidgets(
    'ignored files toggle clears stale children when expanded directory reload fails',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ]
        ..showAllChildrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..failingListChildrenCalls.add(
          const _ListChildrenCall(relativePath: 'src', hideIgnored: false),
        );

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: const _WorkspaceExplorerModeHarness(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);

      await tester.tap(find.byTooltip('Show ignored files'));
      await tester.pumpAndSettle();

      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);
      expect(
        service.listChildrenCalls,
        contains(
          const _ListChildrenCall(relativePath: 'src', hideIgnored: false),
        ),
      );
    },
  );

  testWidgets('save all writes dirty editor documents that are not mounted', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService();
    final registry = EditorSessionRegistry();
    registry.documentFor('tab-1')
      ..attachFile(workspacePath: _workspace().path, relativePath: 'note.txt')
      ..acceptLoaded(
        native.WorkspaceEditorTextFile(
          rawContent: 'original',
          displayContent: 'original',
          contentToken: 'token-1',
          modifiedMillis: 0,
          size: .from(8),
        ),
      )
      ..updateCurrentText('changed');

    await _pumpExplorer(tester, service, registry: registry);
    await tester.tap(find.byTooltip('Save all files'));
    await tester.pumpAndSettle();

    expect(service.writtenFiles, <String, String>{'note.txt': 'changed'});
    expect(registry.isDirty('tab-1'), isFalse);
  });
}
