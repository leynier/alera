part of 'codex_chat_surface_test.dart';

void registerCodexTimelineContextTests() {
  testWidgets('resets pending question selection for a replacement thread', (
    tester,
  ) async {
    Map<String, Object?> request(String id, String question) =>
        <String, Object?>{
          'id': id,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'choice',
                'question': question,
                'options': <Object?>[
                  <String, Object?>{'label': 'Continue'},
                ],
              },
            ],
          },
        };
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: <Object?>[
        request('old-first', 'Old first'),
        request('shared-second', 'Old second'),
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.byTooltip('Next Pending Question'));
    await tester.pump();
    expect(find.text('Request 2 of 2'), findsOneWidget);

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'threadId': 'thread-replacement',
        'snapshot': <String, Object?>{
          'timelineCells': const <Object?>[],
          'pendingRequests': <Object?>[
            request('new-first', 'New first'),
            request('shared-second', 'New second'),
          ],
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(find.text('Request 1 of 2'), findsOneWidget);
    expect(find.text('New first'), findsOneWidget);
  });

  testWidgets('history anchoring ignores output appended during the request', (
    tester,
  ) async {
    List<Object?> messages(int count) => <Object?>[
      for (var index = 0; index < count; index += 1)
        <String, Object?>{
          'id': 'current-$index',
          'turnId': 'current-turn-$index',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Concurrent message $index',
        },
    ];
    final historyGate = Completer<void>();
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      historyNextCursor: 'older',
      historyGate: historyGate,
      pendingRequests: const <Object?>[],
      timelineCells: messages(30),
      historyTimelineCells: <Object?>[
        for (var index = 0; index < 10; index += 1)
          <String, Object?>{
            'id': 'older-$index',
            'turnId': 'older-turn-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Older concurrent message $index',
          },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, height: 400);

    final timeline = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey<String>('codex-timeline-scroll-view')),
    );
    timeline.controller!.jumpTo(AleraTokens.space24);
    await tester.pump();
    final anchor = find.text('Concurrent message 0').first;
    final before = tester.getTopLeft(anchor).dy;

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': messages(31),
          'pendingRequests': const <Object?>[],
        },
      }),
    );
    await tester.pump();
    historyGate.complete();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Concurrent message 0').first).dy,
      closeTo(before, AleraTokens.space2),
    );
    timeline.controller!.jumpTo(timeline.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('Concurrent message 30'), findsWidgets);
  });

  testWidgets('switching tabs releases a pending history load', (tester) async {
    final historyGate = Completer<void>();
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      historyNextCursor: 'older',
      historyGate: historyGate,
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[
        for (var index = 0; index < 30; index += 1)
          <String, Object?>{
            'id': 'current-$index',
            'turnId': 'current-turn-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Switch message $index',
          },
      ],
    );
    addTearDown(client.dispose);

    Future<ScrollController> pumpTab(String tabId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            settingsControllerProvider.overrideWith(_SurfaceSettings.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 400,
                child: CodexChatSurface(
                  workspace: _workspace(),
                  tab: _tab(id: tabId),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      return tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey<String>('codex-timeline-scroll-view')),
          )
          .controller!;
    }

    final first = await pumpTab('codex-tab-1');
    first.jumpTo(AleraTokens.space24);
    await tester.pump();
    await tester.pump();
    expect(
      client.requestTypes.where((type) => type == 'codex.thread.history'),
      hasLength(1),
    );

    final second = await pumpTab('codex-tab-2');
    second.jumpTo(0);
    await tester.pump();
    second.jumpTo(AleraTokens.space24);
    await tester.pump();
    await tester.pump();
    expect(
      client.requestTypes.where((type) => type == 'codex.thread.history'),
      hasLength(2),
    );

    historyGate.complete();
    await tester.pumpAndSettle();
  });
}
