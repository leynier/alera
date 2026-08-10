part of 'codex_chat_surface_test.dart';

void registerCodexToolResponseTests() {
  testWidgets('renders dynamic tool output as structured content', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'dynamic-inspect',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'workspace.inspect',
          'detailsText':
              '[{"type":"inputText","text":"# Ready\\n- **literal output**"}]',
          'metadata': <String, Object?>{
            'itemType': 'dynamicToolCall',
            'tool': 'workspace.inspect',
            'detailsSource': 'contentItems',
            'contentItems': <Object?>[
              <String, Object?>{
                'type': 'inputText',
                'text': '# Ready\n- **literal output**',
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.textContaining('workspace.inspect').first);
    await tester.pump();

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('# Ready\n- **literal output**'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsNothing);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('shows command actions without command output', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'command-actions',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read file',
          'metadata': <String, Object?>{
            'commandActions': <Object?>[
              <String, Object?>{'type': 'read', 'path': '/repo/README.md'},
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(
      find.byKey(const ValueKey<String>('worked-action-command-actions')),
    );
    await tester.pump();

    expect(find.text('Command Actions'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('/repo/README.md'), findsOneWidget);
  });

  testWidgets('counts web searches without calling them files', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-web',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'web-one',
          'turnId': 'turn-web',
          'kind': 'toolCall',
          'status': 'completed',
          'metadata': <String, Object?>{
            'itemType': 'webSearch',
            'query': 'first query',
          },
        },
        <String, Object?>{
          'id': 'web-two',
          'turnId': 'turn-web',
          'kind': 'toolCall',
          'status': 'completed',
          'metadata': <String, Object?>{
            'itemType': 'webSearch',
            'query': 'second query',
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Searched the web 2 times'), findsOneWidget);
    expect(find.text('Searched 2 files'), findsNothing);
  });

  testWidgets('renders structured MCP tool arguments and responses', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'mcp-calendar',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'calendar.lookup',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'server': 'codex_apps',
            'tool': 'calendar.lookup',
            'appContext': <String, Object?>{
              'connectorId': 'connector-internal-id',
              'linkId': 'link-internal-id',
              'appName': 'Google Calendar',
              'actionName': 'Lookup Events',
            },
            'arguments': <String, Object?>{'calendarId': 'work'},
            'result': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'Found 2 events'},
              ],
              'structuredContent': <String, Object?>{'count': 2},
            },
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Used calendar.lookup'), findsOneWidget);
    expect(find.text('Ran 1 command'), findsNothing);
    await tester.tap(find.text('Used calendar.lookup'));
    await tester.pump();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Calendar Id'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.textContaining('connector-internal-id'), findsNothing);
    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Found 2 events'), findsOneWidget);
    expect(find.text('Structured Content'), findsOneWidget);
    expect(find.text('Count'), findsOneWidget);
    expect(find.textContaining('{"content"'), findsNothing);
  });

  testWidgets('keeps empty tool collections visible', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'empty-tool',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'records.empty',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'records.empty',
            'arguments': <String, Object?>{},
            'result': <Object?>[],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used records.empty'));
    await tester.pump();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('No content'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
    expect(find.text('No items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not repeat web search actions as output', (tester) async {
    const action = <String, Object?>{
      'type': 'search',
      'query': 'Flutter structured tool rendering',
    };
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'web-search',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'detailsText':
              '{"type":"search","query":"Flutter structured tool rendering"}',
          'metadata': <String, Object?>{
            'itemType': 'webSearch',
            'query': 'Flutter structured tool rendering',
            'action': action,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(
      find.text('Searched the web for Flutter structured tool rendering'),
    );
    await tester.pump();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets(
    'clears an active selection before streamed tool output changes',
    (tester) async {
      Map<String, Object?> message(String text) => <String, Object?>{
        'id': 'assistant-stream',
        'turnId': 'turn-tools',
        'kind': 'assistantMessage',
        'status': 'inProgress',
        'markdownText': text,
      };
      final client = _SurfaceRuntimeClient(
        pendingRequests: const <Object?>[],
        activeTurnId: 'turn-tools',
        timelineCells: <Object?>[message('First streamed output')],
      );
      addTearDown(client.dispose);
      await _pumpTimelineSegmentSurface(tester, client, settle: false);

      final selection = tester.state<SelectionAreaState>(
        find.byType(SelectionArea).first,
      );
      selection.selectableRegion.selectAll();
      await tester.pump();

      client.emit(
        RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'codex-tab',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[message('Updated streamed output')],
            'pendingRequests': const <Object?>[],
            'activeTurnId': 'turn-tools',
          },
        }),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Updated streamed output'), findsOneWidget);
    },
  );
}
