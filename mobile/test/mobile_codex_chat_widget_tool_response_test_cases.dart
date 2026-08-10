part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexToolResponseTests() {
  testWidgets('mobile renders non-string legacy output', (tester) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'legacy-output',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'legacy.inspect',
          'metadata': <String, Object?>{
            'itemType': 'dynamicToolCall',
            'tool': 'legacy.inspect',
            'detailsSource': 'output',
            'output': <String, Object?>{
              'records': <Object?>[1, 2],
            },
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-legacy-output');

    await tester.tap(find.text('Used legacy.inspect'));
    await tester.pump();

    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('mobile preserves legacy output beside a structured result', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'legacy-output-and-result',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'legacy.inspect',
          'detailsText': 'legacy output',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'legacy.inspect',
            'output': 'legacy output',
            'result': <String, Object?>{'status': 'ready'},
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-legacy-output-result',
    );

    await tester.tap(find.text('Used legacy.inspect'));
    await tester.pump();

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('legacy output'), findsOneWidget);
  });

  testWidgets('mobile renders dynamic tool output as structured content', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
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
            'appContext': <String, Object?>{
              'connectorId': 'connector-internal-id',
              'appName': 'Workspace Browser',
            },
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
    await _pumpScreen(tester, client: client, hostId: 'host-dynamic-tool');

    await tester.tap(find.text('Used workspace.inspect'));
    await tester.pump();

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('# Ready\n- **literal output**'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsNothing);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Workspace Browser'), findsOneWidget);
    expect(find.textContaining('connector-internal-id'), findsNothing);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('mobile keeps empty tool collections visible', (tester) async {
    final client = FakeMobileCodexClient(
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
    await _pumpScreen(tester, client: client, hostId: 'host-empty-tool');

    await tester.tap(find.text('Used records.empty'));
    await tester.pump();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('No content'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
    expect(find.text('No items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile renders file changes as structured details', (
    tester,
  ) async {
    const changes = <Object?>[
      <String, Object?>{
        'path': 'lib/updated.dart',
        'kind': 'update',
        'diff': '@@ -1 +1 @@\n-old\n+new',
      },
    ];
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'structured-file-change',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'title': 'File changes',
          'detailsText': jsonEncode(changes),
          'metadata': const <String, Object?>{
            'itemType': 'fileChange',
            'changes': changes,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-file-change');

    await tester.tap(find.text('File changes'));
    await tester.pump();

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('lib/updated.dart'), findsOneWidget);
    expect(find.text('Diff'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('mobile deduplicates large legacy tool responses', (
    tester,
  ) async {
    final result = <String, Object?>{
      'records': List<String>.generate(300, (index) => 'Record $index'),
    };
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'legacy-large-response',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'records.list',
          'detailsText': jsonEncode(result),
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'records.list',
            'result': result,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-legacy-tool');

    await tester.tap(find.text('Used records.list'));
    await tester.pump();

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('mobile projects only the visible iterable result page', (
    tester,
  ) async {
    final records = _MobileCountingToolIterable(1000);
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'lazy-records',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'records.list',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'records.list',
            'result': records,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-lazy-tool');

    await tester.tap(find.text('Used records.list'));
    await tester.pump();

    expect(records.moveNextCalls, lessThan(100));
    expect(find.text('Record 0'), findsOneWidget);
    expect(find.text('Record 24'), findsNothing);
  });

  testWidgets('mobile summarizes binary content without rendering base64', (
    tester,
  ) async {
    final data = List<String>.filled(20000, 'YWJj').join();
    final result = <String, Object?>{
      'content': <Object?>[
        <String, Object?>{
          'type': 'image',
          'mimeType': 'image/png',
          'data': 'YWJjZA==',
        },
        <String, Object?>{
          'type': 'inputAudio',
          'audioUrl': 'data:audio/wav;base64,$data',
        },
        <String, Object?>{
          'type': 'resource',
          'resource': <String, Object?>{
            'uri': 'memory://audio',
            'mimeType': 'audio/ogg',
            'blob': data,
          },
        },
      ],
    };
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'media-inspect',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'media.inspect',
          'detailsText': jsonEncode(result),
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'media.inspect',
            'result': result,
            'detailsSource': 'result',
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-media-tool');

    await tester.tap(find.text('Used media.inspect'));
    await tester.pump();

    expect(find.text('Image - image/png - 4 B'), findsOneWidget);
    expect(find.textContaining('Audio - audio/wav -'), findsOneWidget);
    expect(find.textContaining('Audio - audio/ogg -'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
    expect(find.text(data), findsNothing);
  });

  testWidgets('mobile bounds deeply nested structured tool content', (
    tester,
  ) async {
    Object? nested = 'leaf';
    for (var depth = 0; depth < 20; depth += 1) {
      nested = <String, Object?>{'level$depth': nested};
    }
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'deep-inspect',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'tree.inspect',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'tree.inspect',
            'result': nested,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-deep-tool');

    await tester.tap(find.text('Used tree.inspect'));
    await tester.pump();

    expect(
      find.text('Nested content hidden at the display depth limit.'),
      findsOneWidget,
    );
    expect(find.text('leaf'), findsNothing);
  });

  testWidgets('mobile bounds large text inside MCP content blocks', (
    tester,
  ) async {
    final largeText = List<String>.filled(65 * 1024, 'x').join();
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'large-text-response',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'documents.read',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'documents.read',
            'result': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': largeText},
              ],
            },
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-large-text-tool');

    await tester.tap(find.text('Used documents.read'));
    await tester.pump();

    expect(find.textContaining('additional characters hidden'), findsOneWidget);
    expect(find.text(largeText), findsNothing);
  });
}

class _MobileCountingToolIterable extends Iterable<String> {
  _MobileCountingToolIterable(this.length);

  @override
  final int length;
  int moveNextCalls = 0;

  @override
  Iterator<String> get iterator => _MobileCountingToolIterator(this);
}

class _MobileCountingToolIterator implements Iterator<String> {
  _MobileCountingToolIterator(this.source);

  final _MobileCountingToolIterable source;
  var _index = -1;

  @override
  String get current => 'Record $_index';

  @override
  bool moveNext() {
    source.moveNextCalls += 1;
    _index += 1;
    return _index < source.length;
  }
}
