part of 'codex_chat_surface_test.dart';

void registerCodexToolLimitsTests() {
  testWidgets('preserves file counts when change details are bounded', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'large-file-change',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'metadata': <String, Object?>{
            'itemType': 'fileChange',
            'changesCount': 40,
            'changes': <Object?>[
              <String, Object?>{
                'truncated': true,
                'message': 'Additional list items were omitted.',
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Edited 40 files'), findsOneWidget);
  });

  testWidgets('reveals large structured tool responses incrementally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'mcp-records',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'records.list',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'records.list',
            'result': <String, Object?>{
              'records': List<String>.generate(
                30,
                (index) => 'Record ${index + 1}',
              ),
            },
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, height: 1400);

    await tester.tap(find.text('Used records.list'));
    await tester.pump();

    expect(find.text('Record 24'), findsOneWidget);
    expect(find.text('Record 25'), findsNothing);
    await tester.tap(find.text('Show 6 More'));
    await tester.pump();
    expect(find.text('Record 30'), findsOneWidget);
  });

  testWidgets('keeps expanded tool pages across same-thread snapshots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, Object?> toolCell() => <String, Object?>{
      'id': 'mcp-records',
      'turnId': 'turn-tools',
      'kind': 'toolCall',
      'status': 'completed',
      'title': 'records.list',
      'metadata': <String, Object?>{
        'itemType': 'mcpToolCall',
        'tool': 'records.list',
        'result': <String, Object?>{
          'records': List<String>.generate(
            30,
            (index) => 'Record ${index + 1}',
          ),
        },
      },
    };
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[toolCell()],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, height: 1400);

    await tester.tap(find.text('Used records.list'));
    await tester.pump();
    await tester.tap(find.text('Show 6 More'));
    await tester.pump();
    expect(find.text('Record 30'), findsOneWidget);

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[toolCell()],
          'pendingRequests': const <Object?>[],
        },
      }),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Record 30'), findsOneWidget);
    expect(find.text('Show 6 More'), findsNothing);
  });

  testWidgets('projects only the visible page of iterable tool results', (
    tester,
  ) async {
    final records = _CountingToolIterable(1000);
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used records.list'));
    await tester.pump();

    expect(records.moveNextCalls, lessThan(200));
    expect(find.text('Record 0'), findsOneWidget);
    expect(find.text('Record 24'), findsNothing);
  });

  testWidgets('summarizes binary tool content without rendering base64', (
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
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used media.inspect'));
    await tester.pump();

    expect(find.text('Image - image/png - 4 B'), findsOneWidget);
    expect(find.textContaining('Audio - audio/wav -'), findsOneWidget);
    expect(find.textContaining('Audio - audio/ogg -'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
    expect(find.text(data), findsNothing);
  });

  testWidgets('bounds deeply nested structured tool content', (tester) async {
    Object? nested = 'leaf';
    for (var depth = 0; depth < 20; depth += 1) {
      nested = <String, Object?>{'level$depth': nested};
    }
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Used tree.inspect'));
    await tester.pump();

    expect(
      find.text('Nested content hidden at the display depth limit.'),
      findsOneWidget,
    );
    expect(find.text('leaf'), findsNothing);
  });
}

class _CountingToolIterable extends Iterable<String> {
  _CountingToolIterable(this.length);

  @override
  final int length;
  int moveNextCalls = 0;

  @override
  Iterator<String> get iterator => _CountingToolIterator(this);
}

class _CountingToolIterator implements Iterator<String> {
  _CountingToolIterator(this.source);

  final _CountingToolIterable source;
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
