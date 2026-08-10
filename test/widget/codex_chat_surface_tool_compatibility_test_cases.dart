part of 'codex_chat_surface_test.dart';

void registerCodexToolCompatibilityTests() {
  testWidgets('renders non-string legacy output from structured metadata', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used legacy.inspect'));
    await tester.pump();

    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('preserves legacy output beside a structured result', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used legacy.inspect'));
    await tester.pump();

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('legacy output'), findsOneWidget);
  });

  testWidgets('renders file changes as structured details', (tester) async {
    const changes = <Object?>[
      <String, Object?>{
        'path': 'lib/updated.dart',
        'kind': 'update',
        'diff': '@@ -1 +1 @@\n-old\n+new',
      },
    ];
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'structured-file-change',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'detailsText': jsonEncode(changes),
          'metadata': const <String, Object?>{
            'itemType': 'fileChange',
            'changes': changes,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('worked-action-structured-file-change'),
      ),
    );
    await tester.pump();

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('lib/updated.dart'), findsOneWidget);
    expect(find.text('Diff'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('deduplicates large responses from legacy snapshots', (
    tester,
  ) async {
    final result = <String, Object?>{
      'records': List<String>.generate(300, (index) => 'Record $index'),
    };
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used records.list'));
    await tester.pump();

    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('bounds large text inside MCP content blocks', (tester) async {
    final largeText = List<String>.filled(65 * 1024, 'x').join();
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used documents.read'));
    await tester.pump();

    expect(find.textContaining('additional characters hidden'), findsOneWidget);
    expect(find.text(largeText), findsNothing);
  });
}
