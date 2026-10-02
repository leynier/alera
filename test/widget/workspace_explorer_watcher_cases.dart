part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerWatcherTests() {
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

  testWidgets('coalesces watcher batches while a directory refresh is busy', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];

    await _pumpExplorer(tester, service);
    final listGate = Completer<void>();
    service.listChildrenGate = listGate;
    service.childrenByDirectory[''] = <native.WorkspaceFileEntry>[
      _file('external.dart'),
      _file('readme.md'),
    ];
    service.emitWatchBatch(<String>['']);
    await tester.pump();
    for (var index = 0; index < 100; index += 1) {
      service.emitWatchBatch(<String>['']);
    }
    await tester.pump();
    listGate.complete();
    await tester.pumpAndSettle();

    final rootLoads = service.listChildrenCalls
        .where((call) => call.relativePath.isEmpty)
        .length;
    expect(rootLoads, lessThanOrEqualTo(3));
    expect(find.text('external.dart'), findsOneWidget);
  });

  testWidgets('preserves sibling directories when loads overlap', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('one', hasChildrenHint: true),
        _directory('two', hasChildrenHint: true),
      ]
      ..childrenByDirectory['one'] = <native.WorkspaceFileEntry>[
        _file('one/first.dart'),
      ]
      ..childrenByDirectory['two'] = <native.WorkspaceFileEntry>[
        _file('two/second.dart'),
      ];

    await _pumpExplorer(tester, service);

    final oneListGate = Completer<void>();
    final twoListGate = Completer<void>();
    final oneProjectionGate = Completer<void>();
    final twoProjectionGate = Completer<void>();
    service
      ..listChildrenGatesByDirectory['one'] = oneListGate
      ..listChildrenGatesByDirectory['two'] = twoListGate
      ..projectionGatesByDirectory['one'] = oneProjectionGate
      ..projectionGatesByDirectory['two'] = twoProjectionGate
      ..projectionCallDirectories.clear()
      .._projectionCallCount = 0;

    await tester.tap(find.text('one'));
    await tester.tap(find.text('two'));
    await tester.pump();

    oneListGate.complete();
    twoListGate.complete();
    await tester.pump();

    expect(service.projectionCallDirectories, hasLength(1));
    final firstDirectory = service.projectionCallDirectories.single;
    expect(firstDirectory, anyOf('one', 'two'));
    (firstDirectory == 'one' ? oneProjectionGate : twoProjectionGate)
        .complete();
    await tester.pump();

    expect(service.projectionCallDirectories, hasLength(2));
    final secondDirectory = service.projectionCallDirectories.last;
    expect(secondDirectory, isNot(firstDirectory));
    (secondDirectory == 'one' ? oneProjectionGate : twoProjectionGate)
        .complete();
    await tester.pumpAndSettle();

    expect(find.text('first.dart'), findsOneWidget);
    expect(find.text('second.dart'), findsOneWidget);
  });

  testWidgets(
    'keeps the newest watcher paths after an older update completes',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('one', hasChildrenHint: true),
          _directory('two', hasChildrenHint: true),
        ]
        ..childrenByDirectory['one'] = <native.WorkspaceFileEntry>[
          _file('one/first.dart'),
        ]
        ..childrenByDirectory['two'] = <native.WorkspaceFileEntry>[
          _file('two/second.dart'),
        ];

      await _pumpExplorer(tester, service);
      service
        ..watchedPathUpdates.clear()
        ..watcherUpdateCallCount = 0
        ..projectionCallDirectories.clear()
        .._projectionCallCount = 0;
      final oneProjectionGate = Completer<void>();
      final twoProjectionGate = Completer<void>();
      final oldUpdateGate = Completer<void>();
      final newUpdateGate = Completer<void>();
      service
        ..projectionGatesByDirectory['one'] = oneProjectionGate
        ..projectionGatesByDirectory['two'] = twoProjectionGate;
      service.watcherUpdateGates
        ..clear()
        ..add(oldUpdateGate)
        ..add(newUpdateGate);

      await tester.tap(find.text('one'));
      await tester.tap(find.text('two'));
      await tester.pump();

      expect(service.projectionCallDirectories, hasLength(1));
      final firstDirectory = service.projectionCallDirectories.single;
      (firstDirectory == 'one' ? oneProjectionGate : twoProjectionGate)
          .complete();
      await tester.pump();
      expect(service.watcherUpdateCallCount, 1);
      expect(service.projectionCallDirectories, hasLength(2));

      final secondDirectory = service.projectionCallDirectories.last;
      (secondDirectory == 'one' ? oneProjectionGate : twoProjectionGate)
          .complete();
      await tester.pump();
      expect(service.watcherUpdateCallCount, 1);

      oldUpdateGate.complete();
      await tester.pump();
      expect(service.watcherUpdateCallCount, 2);

      newUpdateGate.complete();
      await tester.pumpAndSettle();

      expect(service.watchedPathUpdates, hasLength(2));
      expect(service.watchedPathUpdates.first, contains(firstDirectory));
      expect(service.watchedPathUpdates.last, contains(secondDirectory));
    },
  );

  testWidgets('drops an older tree projection after a newer refresh', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    await _pumpExplorer(tester, service);

    final oldProjectionGate = Completer<void>();
    final newProjectionGate = Completer<void>();
    service._projectionCallCount = 0;
    service
      ..projectionGates.add(oldProjectionGate)
      ..projectionGates.add(newProjectionGate)
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('old.dart'),
      ];
    service.emitWatchBatch(<String>['']);
    await tester.pump();

    service.childrenByDirectory[''] = <native.WorkspaceFileEntry>[
      _file('new.dart'),
    ];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    oldProjectionGate.complete();
    await tester.pump();
    expect(service._projectionCallCount, 2);

    newProjectionGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsOneWidget);
    expect(find.text('old.dart'), findsNothing);
  });

  testWidgets(
    'waits for the previous watcher before starting a new workspace',
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
      final harnessKey = GlobalKey<_ExplorerWorkspaceSwitchHarnessState>();

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: _ExplorerWorkspaceSwitchHarness(
                  key: harnessKey,
                  workspace: _workspace(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(service.startWatcherCalls, 1);

      harnessKey.currentState!.switchWorkspace(
        _workspace(
          id: 'workspace-2',
          name: 'Feature',
          path: '/repo/alera-feature',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.idle();

      expect(harnessKey.currentState!.workspacePath, '/repo/alera-feature');
      expect(find.text('main.dart'), findsNothing);
      expect(find.text('feature.dart'), findsNothing);
      expect(service.stopWatcherCalls, 1);
      expect(service.startWatcherCalls, 1);
      expect(service.startCalledWhileStopPending, isFalse);

      stopGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('feature.dart'), findsOneWidget);
      expect(service.startWatcherCalls, 2);
    },
  );
}
