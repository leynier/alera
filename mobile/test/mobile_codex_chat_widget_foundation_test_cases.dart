part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexFoundationTests() {
  test('mobile draft store preserves every abandoned submission', () {
    final store = MobileCodexComposerDraftStore();
    store.write(
      'host',
      'tab',
      const MobileCodexComposerDraft(
        value: TextEditingValue(text: 'Current draft'),
      ),
    );

    store.restoreSubmission(
      'host',
      'tab',
      const MobileCodexComposerDraft(
        value: TextEditingValue(text: 'First submission'),
        attachments: <Map<String, Object?>>[
          <String, Object?>{'path': 'first.md'},
        ],
      ),
    );
    store.restoreSubmission(
      'host',
      'tab',
      const MobileCodexComposerDraft(
        value: TextEditingValue(text: 'Second submission'),
        attachments: <Map<String, Object?>>[
          <String, Object?>{'path': 'second.md'},
        ],
      ),
    );

    final restored = store.read('host', 'tab');
    expect(
      restored.value.text,
      'Current draft\n\nFirst submission\n\nSecond submission',
    );
    expect(
      restored.attachments.map((attachment) => attachment['path']),
      <String>['first.md', 'second.md'],
    );
  });

  test('mobile draft store does not restore a closed tab', () {
    final store = MobileCodexComposerDraftStore();
    const submission = MobileCodexComposerDraft(
      value: TextEditingValue(text: 'Abandoned submission'),
    );

    store.write('host', 'tab', submission);
    store.remove('host', 'tab');
    store.restoreSubmission('host', 'tab', submission);

    expect(store.read('host', 'tab').isEmpty, isTrue);

    store.activate('host', 'tab');
    store.restoreSubmission('host', 'tab', submission);

    expect(store.read('host', 'tab').value.text, 'Abandoned submission');
  });

  test('mobile draft store delivers an upload that outlived its screen', () {
    // The picker backgrounds the app, and the host reconnect that follows
    // rebuilds the tab body while the bytes are still streaming, so the state
    // that started the pick is usually gone when the path comes back.
    final store = MobileCodexComposerDraftStore();
    var restored = 0;
    store.addRestoreListener('host', 'tab', () => restored += 1);
    store.write(
      'host',
      'tab',
      const MobileCodexComposerDraft(
        value: TextEditingValue(text: 'Look at this'),
      ),
    );

    store.addAttachment('host', 'tab', <String, Object?>{
      'type': 'localImage',
      'path': '/host/prompt-images/shot.png',
    });

    expect(restored, 1);
    final draft = store.read('host', 'tab');
    expect(draft.value.text, 'Look at this');
    expect(draft.attachments.single['path'], '/host/prompt-images/shot.png');

    store.remove('host', 'tab');
    store.addAttachment('host', 'tab', <String, Object?>{'path': 'late.png'});
    expect(store.read('host', 'tab').isEmpty, isTrue);
  });

  testWidgets('hides session actions for older runtimes', (tester) async {
    final client = FakeMobileCodexClient(supportsCodexSessions: false);
    addTearDown(client.dispose);

    await _pumpScreen(tester, client: client, hostId: 'host-legacy');

    expect(find.byTooltip('Codex Chat Actions'), findsNothing);
    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/rename Legacy Work');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final rename = client.calls.lastWhere(
      (call) => call.type == 'codex.thread.rename',
    );
    expect(rename.payload, <String, Object?>{
      'tabId': 'tab-host-legacy',
      'name': 'Legacy Work',
    });

    await tester.enterText(composer, '/new');
    await tester.pump();
    expect(find.text('New'), findsNothing);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(
      client.calls.where((call) => call.type == 'codex.thread.new'),
      isEmpty,
    );
    expect((tester.widget<TextField>(composer).controller?.text), '/new');
  });

  test('mobile workspace links parse Markdown fragments and line suffixes', () {
    final fragment = parseMobileCodexWorkspaceLink('lib/a%20file.dart#L42');
    expect(fragment.path, 'lib/a file.dart');
    expect(fragment.line, 42);

    final suffix = parseMobileCodexWorkspaceLink('README.md:17');
    expect(suffix.path, 'README.md');
    expect(suffix.line, 17);

    final fileUri = parseMobileCodexWorkspaceLink(
      'file:///repo/lib/main.dart#L23',
    );
    expect(fileUri.path, '/repo/lib/main.dart');
    expect(fileUri.line, 23);

    final windowsFileUri = parseMobileCodexWorkspaceLink(
      'file:///C:/repo/lib/main.dart#L24',
    );
    expect(windowsFileUri.path, 'C:/repo/lib/main.dart');
    expect(windowsFileUri.line, 24);

    final attachment = mobileCodexPathTarget(
      '/repo/C#notes.md',
      parseLineReferences: false,
    );
    expect(attachment.path, '/repo/C#notes.md');
    expect(attachment.line, isNull);

    final markdownLink = mobileCodexPathTarget(
      '/repo/C%23notes.md#L25',
      parseLineReferences: true,
    );
    expect(markdownLink.path, '/repo/C#notes.md');
    expect(markdownLink.line, 25);

    expect(
      mobileCodexWorkspaceRelativePath(
        path: '/repo/lib/main.dart',
        cwd: '/repo',
      ),
      'lib/main.dart',
    );
    expect(
      mobileCodexWorkspaceRelativePath(
        path: r'C:\repo\lib\main.dart',
        cwd: r'c:\repo',
      ),
      'lib/main.dart',
    );
    expect(
      mobileCodexWorkspaceRelativePath(
        path: '/runtime/prompt-files/upload.md',
        cwd: '/repo',
      ),
      isNull,
    );
  });

  testWidgets('mobile hides plan progress outside the active turn', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-current',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'plan-progress',
            'kind': 'plan',
            'turnId': 'turn-completed',
            'status': 'completed',
            'metadata': <String, Object?>{
              'plan': <Object?>[
                <String, Object?>{'step': 'Inspect', 'status': 'completed'},
                <String, Object?>{'step': 'Build', 'status': 'inProgress'},
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);

    await _pumpScreen(tester, client: client, hostId: 'host-stale-progress');

    expect(find.text('Step 2 / 2'), findsNothing);
  });

  testWidgets('mobile Quick Open reports start failures and retries', (
    tester,
  ) async {
    var attempts = 0;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStarter: (_, _) {
        attempts += 1;
        if (attempts == 1) return Future.error(StateError('unavailable'));
        return Future.value(
          const MobileWorkspaceQuickOpenSession(
            id: 'retry-session',
            indexedFileCount: 1,
          ),
        );
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-quick-open-error');

    await tester.tap(find.byTooltip('Add Attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace File'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace files could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('docs/notes.md'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('mobile stops Quick Open when its picker closes during start', (
    tester,
  ) async {
    final start = Completer<MobileWorkspaceQuickOpenSession>();
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStart: start.future,
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-quick-open');

    await tester.tap(find.byTooltip('Add Attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace File'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    const session = MobileWorkspaceQuickOpenSession(
      id: 'late-session',
      indexedFileCount: 1,
    );
    start.complete(session);
    await tester.pumpAndSettle();

    expect(client.stoppedQuickOpenSessions, <Object>[session]);
    expect(client.quickOpenSearchCount, 0);
  });

  testWidgets('mobile catches Quick Open teardown failures', (tester) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStopper: (_) =>
          Future<void>.error(StateError('host disconnected')),
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stop-error');

    await tester.tap(find.byTooltip('Add Attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace File'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile recreates an expired Quick Open session on retry', (
    tester,
  ) async {
    var starts = 0;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStarter: (_, _) async =>
          MobileWorkspaceQuickOpenSession(
            id: 'session-${++starts}',
            indexedFileCount: 1,
          ),
      workspaceQuickOpenSearcher: (session, query, limit) {
        if (session.id == 'session-1') {
          return Future.error(StateError('Quick Open session expired'));
        }
        return Future.value(const <MobileWorkspaceQuickOpenMatch>[
          MobileWorkspaceQuickOpenMatch(
            relativePath: 'docs/notes.md',
            score: 1,
          ),
        ]);
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-expired-session');

    await tester.tap(find.byTooltip('Add Attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace File'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace files could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('docs/notes.md'), findsOneWidget);
    expect(starts, 2);
    expect(
      client.stoppedQuickOpenSessions.map((session) => session.id),
      contains('session-1'),
    );
  });

  testWidgets('mobile stops catalog Quick Open when the chat unmounts', (
    tester,
  ) async {
    final start = Completer<MobileWorkspaceQuickOpenSession>();
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStart: start.future,
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-catalog-close');

    await tester.enterText(find.byType(TextField).last, '@notes');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());

    const session = MobileWorkspaceQuickOpenSession(
      id: 'late-catalog-session',
      indexedFileCount: 1,
    );
    start.complete(session);
    await tester.pumpAndSettle();

    expect(client.stoppedQuickOpenSessions, contains(session));
    expect(client.quickOpenSearchCount, 0);
  });

  testWidgets('mobile replaces a pending Quick Open start after cwd changes', (
    tester,
  ) async {
    final oldStart = Completer<MobileWorkspaceQuickOpenSession>();
    final newStart = Completer<MobileWorkspaceQuickOpenSession>();
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStarter: (_, cwd) =>
          cwd == '/repo/new' ? newStart.future : oldStart.future,
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-cwd-race');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@notes');
    await tester.pump(const Duration(milliseconds: 300));
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-cwd-race',
        'cwd': '/repo/new',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    const current = MobileWorkspaceQuickOpenSession(
      id: 'current-session',
      indexedFileCount: 1,
    );
    newStart.complete(current);
    await tester.pumpAndSettle();
    const stale = MobileWorkspaceQuickOpenSession(
      id: 'stale-session',
      indexedFileCount: 1,
    );
    oldStart.complete(stale);
    await tester.pumpAndSettle();

    expect(client.searchedQuickOpenSessions, <Object>[current]);
    expect(client.stoppedQuickOpenSessions, contains(stale));
  });

  testWidgets('mobile keeps replacement Quick Open when stale search fails', (
    tester,
  ) async {
    final staleSearch = Completer<List<MobileWorkspaceQuickOpenMatch>>();
    const stale = MobileWorkspaceQuickOpenSession(
      id: 'stale-search-session',
      indexedFileCount: 1,
    );
    const current = MobileWorkspaceQuickOpenSession(
      id: 'current-search-session',
      indexedFileCount: 1,
    );
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/current.md'],
      workspaceQuickOpenStarter: (_, cwd) async =>
          cwd == '/repo/new' ? current : stale,
      workspaceQuickOpenSearcher: (session, query, limit) {
        if (session.id == stale.id) return staleSearch.future;
        return Future.value(const <MobileWorkspaceQuickOpenMatch>[
          MobileWorkspaceQuickOpenMatch(
            relativePath: 'docs/current.md',
            score: 1,
          ),
        ]);
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-search-race');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@current');
    await tester.pump(const Duration(milliseconds: 300));
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-search-race',
        'cwd': '/repo/new',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('docs/current.md'), findsOneWidget);

    staleSearch.completeError(StateError('stale search failed'));
    await tester.pumpAndSettle();

    expect(client.stoppedQuickOpenSessions, isNot(contains(current)));
    expect(find.text('docs/current.md'), findsOneWidget);
  });
}
