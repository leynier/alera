part of 'terminal_tab_view_test.dart';

void _registerTerminalTabEntryRefreshTests() {
  testWidgets('opening a terminal refreshes the measured viewport once', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'tab-1', title: 'Terminal 1'),
        fakeTab(id: 'tab-2', title: 'Terminal 2'),
      ];
    addTearDown(client.dispose);
    await _pumpTab(tester, client);
    final terminal = _terminalOf(tester);
    final calls = _entryRefreshResizeCalls(
      'session-tab-1',
      terminal.viewWidth,
      terminal.viewHeight,
    );
    expect(_resizeCalls(client), calls);
    expect(client.attachments.map((attachment) => attachment.tabId), ['tab-1']);

    client.emitOutput(
      'session-tab-1',
      Uint8List.fromList(utf8.encode('live output')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(_resizeCalls(client), calls);
    expect(_terminalOf(tester), same(terminal));
    expect(terminal.buffer.getText(), contains('live output'));
    expect(client.writes, isEmpty);
    expect(client.calls.where((call) => call.startsWith('restart ')), isEmpty);
  });

  testWidgets('selecting another mobile tab refreshes only that terminal', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'tab-1', title: 'Terminal 1'),
        fakeTab(id: 'tab-2', title: 'Terminal 2'),
      ];
    addTearDown(client.dispose);
    await _pumpEntryWorkspace(tester, client);
    final first = _terminalOf(tester);
    final firstCalls = _entryRefreshResizeCalls(
      'session-tab-1',
      first.viewWidth,
      first.viewHeight,
    );
    expect(_resizeCalls(client), firstCalls);

    await tester.tap(find.text('Terminal 2'));
    await tester.pumpAndSettle();
    final second = _terminalOf(tester);
    final secondCalls = _entryRefreshResizeCalls(
      'session-tab-2',
      second.viewWidth,
      second.viewHeight,
    );
    expect(_resizeCalls(client), [...firstCalls, ...secondCalls]);

    await tester.tap(find.text('Terminal 2'));
    await tester.pumpAndSettle();
    expect(_resizeCalls(client), [...firstCalls, ...secondCalls]);

    await tester.tap(find.text('Terminal 1'));
    await tester.pumpAndSettle();
    expect(_resizeCalls(client), [
      ...firstCalls,
      ...secondCalls,
      ...firstCalls,
    ]);
    expect(client.calls.where((call) => call.startsWith('restart ')), isEmpty);
  });

  testWidgets(
    'returning to a retained terminal refreshes without reattaching',
    (tester) async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      addTearDown(client.dispose);
      await _pumpTab(tester, client);
      final terminal = _terminalOf(tester);
      terminal.write('retained history');
      await tester.pumpAndSettle();
      final buffer = terminal.buffer.getText();
      final callsBefore = _resizeCalls(client);
      final navigator = Navigator.of(
        tester.element(find.byType(TerminalTabView)),
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Another Screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_resizeCalls(client), callsBefore);

      navigator.pop();
      await tester.pumpAndSettle();
      final pulse = terminalViewportRefreshPulseSize(
        terminal.viewWidth,
        terminal.viewHeight,
      );
      expect(_resizeCalls(client), [
        ...callsBefore,
        'resize session-tab-1 ${pulse.$1} ${pulse.$2}',
        'resize session-tab-1 ${terminal.viewWidth} ${terminal.viewHeight}',
      ]);
      expect(_terminalOf(tester), same(terminal));
      expect(terminal.buffer.getText(), buffer);
      expect(client.attachments, hasLength(1));
    },
  );

  testWidgets('entry refresh waits until restored history has drained', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachmentSnapshot = utf8.encode(
        '${'restored history ' * 8}\r\n' * 1500,
      )
      ..attachmentSnapshotCols = 200
      ..attachmentSnapshotRows = 50;
    addTearDown(client.dispose);
    await _pumpTab(tester, client, settle: false);
    expect(find.text('Restoring terminal'), findsOneWidget);
    expect(_resizeCalls(client), isEmpty);

    await _drainRestore(tester);
    final terminal = _terminalOf(tester);
    expect(
      _resizeCalls(client),
      _entryRefreshResizeCalls(
        'session-tab-1',
        terminal.viewWidth,
        terminal.viewHeight,
      ),
    );
    expect(terminal.buffer.getText(), contains('restored history'));
    expect(client.writes, isEmpty);
  });

  testWidgets('route return waits for the pending viewport acknowledgement', (
    tester,
  ) async {
    final client = _DelayedViewportClient()
      ..tabs = [fakeTab(id: 'tab-1', title: 'Terminal 1')];
    addTearDown(client.dispose);
    await _pumpTab(tester, client);
    final terminal = _terminalOf(tester);
    final navigator = Navigator.of(
      tester.element(find.byType(TerminalTabView)),
    );
    expect(_resizeCalls(client), hasLength(1));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another Screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(_resizeCalls(client), hasLength(1));

    client.viewportAcknowledged.complete();
    await tester.pumpAndSettle();
    expect(
      _resizeCalls(client),
      _entryRefreshResizeCalls(
        'session-tab-1',
        terminal.viewWidth,
        terminal.viewHeight,
      ),
    );
    expect(_terminalOf(tester), same(terminal));
    expect(client.attachments, hasLength(1));
  });

  testWidgets('late attachment cannot refresh a terminal that was left', (
    tester,
  ) async {
    final attached = Completer<void>();
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'tab-1', title: 'Terminal 1'),
        fakeTab(id: 'tab-2', title: 'Terminal 2'),
      ]
      ..attachCompletion = attached.future;
    addTearDown(client.dispose);
    await _pumpEntryWorkspace(tester, client, settle: false);
    expect(client.calls, contains('attach tab-1'));
    client.attachCompletion = null;
    await tester.tap(find.text('Terminal 2'));
    await tester.pumpAndSettle();
    final second = _terminalOf(tester);
    attached.complete();
    await tester.pumpAndSettle();

    expect(
      _resizeCalls(client),
      _entryRefreshResizeCalls(
        'session-tab-2',
        second.viewWidth,
        second.viewHeight,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning during a refresh waits for its pulse to finish', (
    tester,
  ) async {
    final client = _DelayedViewportClient(delayAfterCalls: 3)
      ..tabs = [fakeTab(id: 'tab-1', title: 'Terminal 1')];
    addTearDown(client.dispose);
    await _pumpTab(tester, client);
    final terminal = _terminalOf(tester);
    final navigator = Navigator.of(
      tester.element(find.byType(TerminalTabView)),
    );
    expect(_resizeCalls(client), hasLength(4));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another Screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(_resizeCalls(client), hasLength(4));

    client.viewportAcknowledged.complete();
    await tester.pumpAndSettle();
    final pulse = terminalViewportRefreshPulseSize(
      terminal.viewWidth,
      terminal.viewHeight,
    );
    expect(_resizeCalls(client), [
      ..._entryRefreshResizeCalls(
        'session-tab-1',
        terminal.viewWidth,
        terminal.viewHeight,
      ),
      'resize session-tab-1 ${pulse.$1} ${pulse.$2}',
      'resize session-tab-1 ${terminal.viewWidth} ${terminal.viewHeight}',
    ]);
    expect(_terminalOf(tester), same(terminal));
    expect(client.attachments, hasLength(1));
  });
}

class _DelayedViewportClient extends FakeTerminalClient {
  _DelayedViewportClient({this.delayAfterCalls = 0});

  final int delayAfterCalls;
  int _resizeCount = 0;
  final viewportAcknowledged = Completer<void>();

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {
    await super.resizeTerminal(sessionId, cols, rows);
    if (++_resizeCount > delayAfterCalls) {
      await viewportAcknowledged.future;
    }
  }
}

Future<void> _pumpEntryWorkspace(
  WidgetTester tester,
  FakeTerminalClient client, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        accessoryLayoutRepositoryProvider.overrideWithValue(
          MemoryAccessoryLayoutRepository(),
        ),
        terminalClipboardSettingsControllerProvider.overrideWith(
          () => _FixedTerminalClipboardSettings(false),
        ),
      ],
      child: const MaterialApp(
        home: WorkspaceTabsScreen(
          hostId: 'host-1',
          workspace: WorkspaceSummary(
            id: 'workspace-1',
            projectId: 'project-1',
            name: 'Workspace',
            path: '/repo',
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump();
      if (find.text('Terminal 2').evaluate().isNotEmpty) return;
    }
    fail('the workspace tabs never loaded');
  }
}
