part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression3Tests() {
  testWidgets('mobile preserves skill and app selections with the same name', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.skills.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'shared', 'path': '/skills/shared'},
          ],
        },
        'codex.apps.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'shared', 'connectorId': 'app-shared'},
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-shared-catalog');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, r'$sha');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'shared').first);
    await tester.pump();
    await tester.enterText(composer, r'$shared $sha');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'shared').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{
        'type': 'skill',
        'name': 'shared',
        'path': '/skills/shared',
      },
      <String, Object?>{
        'type': 'mention',
        'name': 'shared',
        'path': 'app://app-shared',
      },
      <String, Object?>{'type': 'text', 'text': r'$shared $shared'},
    ]);
  });

  testWidgets('mobile ignores a stale Quick Open search failure', (
    tester,
  ) async {
    final firstSearch = Completer<List<MobileWorkspaceQuickOpenMatch>>();
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      workspaceQuickOpenSearcher: (session, query, limit) {
        if (query == 'first') return firstSearch.future;
        return Future.value(const <MobileWorkspaceQuickOpenMatch>[
          MobileWorkspaceQuickOpenMatch(
            relativePath: 'docs/second.md',
            score: 1,
          ),
        ]);
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-search-race');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@first');
    await tester.pump(const Duration(milliseconds: 220));
    await tester.enterText(composer, '@second');
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.text('docs/second.md'), findsOneWidget);

    firstSearch.completeError(StateError('stale search failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('docs/second.md'), findsOneWidget);
    expect(client.stoppedQuickOpenSessions, isEmpty);
  });

  testWidgets('mobile saved prompts override colliding slash actions', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      savedPrompts: const <MobileCodexSavedPrompt>[
        MobileCodexSavedPrompt(
          name: 'compact',
          description: 'Run a custom compact workflow.',
          body: 'Expanded compact prompt',
          scope: 'repo',
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-prompt-collision');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/comp');
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'compact'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'compact'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.compact'),
      isEmpty,
    );
    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Expanded compact prompt',
    });
  });

  testWidgets('mobile catalog reserves a full two-line row height', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-catalog-height');

    await tester.enterText(find.byType(TextField).last, '/res');
    await tester.pump();

    expect(
      tester.getSize(find.widgetWithText(ListTile, 'Resume')).height,
      AleraTokens.codexCatalogRowHeight,
    );
  });

  testWidgets('mobile disables session actions during an active turn', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-active',
        'timelineCells': <Object?>[],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-busy-sessions');

    final menu = find.ancestor(
      of: find.byTooltip('Codex Chat Actions'),
      matching: find.byType(PopupMenuButton<String>),
    );
    expect(tester.widget<PopupMenuButton<String>>(menu).enabled, isFalse);
  });

  testWidgets('mobile surfaces failures in grouped activity', (tester) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'failed-command',
          'turnId': 'turn-failed-tools',
          'kind': 'command',
          'status': 'failed',
          'title': 'broken command',
          'metadata': <String, Object?>{'itemType': 'commandExecution'},
        },
        <String, Object?>{
          'id': 'completed-read',
          'turnId': 'turn-failed-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'Read file',
          'metadata': <String, Object?>{'itemType': 'fileRead'},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-failed-tools');

    final summary = find.text('Read 1 file, Ran 1 command · Failed');
    expect(summary, findsOneWidget);
    expect(tester.widget<Text>(summary).style?.color, AleraTokens.error);
  });

  testWidgets(
    'mobile scrolls a footer whose flexible content exceeds the body',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = FakeMobileCodexClient(
        initialSnapshot: const <String, Object?>{
          'activeTurnId': 'turn-footer',
          'timelineCells': <Object?>[],
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-footer-scroll',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      container
          .read(mobileCodexComposerDraftStoreProvider)
          .write(
            'host-footer-scroll',
            'tab-host-footer-scroll',
            MobileCodexComposerDraft(
              attachments: <Map<String, Object?>>[
                for (var index = 0; index < 12; index++)
                  <String, Object?>{
                    'type': 'file',
                    'name': 'attachment-$index.md',
                    'path': '/tmp/attachment-$index.md',
                  },
              ],
            ),
          );
      await _pumpScreen(
        tester,
        client: client,
        hostId: 'host-footer-scroll',
        container: container,
      );
      final controller = container.read(
        mobileCodexControllerProvider(
          'host-footer-scroll',
          'tab-host-footer-scroll',
        ).notifier,
      );
      for (var index = 0; index < 12; index++) {
        await controller.send('Queued message $index');
      }
      await tester.pump();

      expect(find.text('Queued Messages'), findsOneWidget);
      expect(find.text('attachment-0.md'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
