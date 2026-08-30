part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression4Tests() {
  testWidgets('mobile launches external links without a query preflight', (
    tester,
  ) async {
    final previousPlatform = UrlLauncherPlatform.instance;
    final launcher = _LaunchWithoutQueryUrlLauncherPlatform();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'external-link-without-query',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[Email](mailto:user@example.com)',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-direct-link');

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(launcher.launches, 1);
    expect(find.text('Could not open link.'), findsNothing);
  });

  testWidgets('mobile does not re-resolve a selected spaced catalog item', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.apps.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'Google', 'connectorId': 'google'},
            <String, Object?>{
              'name': 'Google Drive',
              'connectorId': 'google-drive',
            },
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-spaced-overlap');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, r'$Drive');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Google Drive'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{
        'type': 'mention',
        'name': 'Google Drive',
        'path': 'app://google-drive',
      },
      <String, Object?>{'type': 'text', 'text': r'$Google Drive'},
    ]);
  });

  testWidgets('mobile history anchor ignores concurrently appended rows', (
    tester,
  ) async {
    final history = Completer<Map<String, Object?>>();
    List<Object?> recentCells({bool includeAppended = false}) => <Object?>[
      for (var index = 0; index < 20; index++)
        <String, Object?>{
          'id': 'concurrent-recent-$index',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Concurrent recent message $index.',
        },
      if (includeAppended)
        for (var index = 0; index < 8; index++)
          <String, Object?>{
            'id': 'concurrent-appended-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Concurrently appended message $index.',
          },
    ];
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) async {
        if (type == 'codex.thread.open') {
          return <String, Object?>{
            'threadId': 'thread-concurrent-history',
            'historyNextCursor': 'older',
            'snapshot': <String, Object?>{'timelineCells': recentCells()},
          };
        }
        if (type == 'codex.thread.history') return history.future;
        return <String, Object?>{};
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-concurrent-history')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-concurrent-history',
      container: container,
    );
    final anchorKey = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'cell-concurrent-recent-',
              ),
        )
        .evaluate()
        .map((element) => element.widget.key! as ValueKey<String>)
        .first;
    final anchor = find.byKey(anchorKey);
    final topBefore = tester.getTopLeft(anchor).dy;

    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pump();
    client.emit(
      MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-concurrent-history',
        'threadId': 'thread-concurrent-history',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': recentCells(includeAppended: true).sublist(20),
        },
      }),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();
    expect(
      container
          .read(
            mobileCodexControllerProvider(
              'host-concurrent-history',
              'tab-host-concurrent-history',
            ),
          )
          .value!
          .timelineCells,
      hasLength(28),
    );
    history.complete(<String, Object?>{
      'snapshot': <String, Object?>{
        'timelineCells': <Object?>[
          for (var index = 0; index < 20; index++)
            <String, Object?>{
              'id': 'concurrent-older-$index',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Concurrent older message $index.',
            },
        ],
      },
    });
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, closeTo(topBefore, 1));
    expect(
      container
          .read(
            mobileCodexControllerProvider(
              'host-concurrent-history',
              'tab-host-concurrent-history',
            ),
          )
          .value!
          .timelineCells
          .any((cell) => cell.id == 'concurrent-appended-7'),
      isTrue,
    );
  });

  testWidgets('mobile history anchor preserves merged activity boundaries', (
    tester,
  ) async {
    final history = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) async {
        if (type == 'codex.thread.open') {
          return <String, Object?>{
            'threadId': 'thread-merged-history',
            'historyNextCursor': 'older',
            'snapshot': <String, Object?>{
              'timelineCells': <Object?>[
                for (var index = 0; index < 2; index++)
                  <String, Object?>{
                    'id': 'recent-command-$index',
                    'kind': 'command',
                    'status': 'completed',
                    'turnId': 'shared-turn',
                    'title': 'Recent command $index',
                  },
                for (var index = 0; index < 20; index++)
                  <String, Object?>{
                    'id': 'merged-anchor-$index',
                    'kind': 'assistantMessage',
                    'status': 'completed',
                    'markdownText': 'Anchor message $index.',
                  },
              ],
            },
          };
        }
        if (type == 'codex.thread.history') return history.future;
        return <String, Object?>{};
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-merged-history');
    final anchor = find.byKey(const ValueKey<String>('cell-merged-anchor-0'));
    final topBefore = tester.getTopLeft(anchor).dy;

    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pump();
    history.complete(<String, Object?>{
      'snapshot': <String, Object?>{
        'timelineCells': <Object?>[
          for (var index = 0; index < 8; index++)
            <String, Object?>{
              'id': 'older-message-$index',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Older message $index.',
            },
          for (var index = 0; index < 2; index++)
            <String, Object?>{
              'id': 'older-command-$index',
              'kind': 'command',
              'status': 'completed',
              'turnId': 'shared-turn',
              'title': 'Older command $index',
            },
        ],
      },
    });
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, closeTo(topBefore, 1));
  });

  testWidgets('mobile reports previews unavailable on older runtimes', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'legacy-attachment',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Open the attachment.',
          'metadata': <String, Object?>{
            'attachments': <Object?>[
              <String, Object?>{
                'path': '/tmp/report.csv',
                'displayName': 'report.csv',
                'kind': 'file',
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-legacy-preview');

    await tester.tap(find.text('report.csv'));
    await tester.pumpAndSettle();

    expect(
      find.text('File preview requires a newer Alera runtime.'),
      findsOneWidget,
    );
  });
}
