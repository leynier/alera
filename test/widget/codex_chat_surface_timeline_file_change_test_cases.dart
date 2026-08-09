part of 'codex_chat_surface_test.dart';

void registerCodexTimelineFileChangeTests() {
  testWidgets('omits completed file change placeholders without changes', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-tools',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'diff-real',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'metadata': <String, Object?>{
            'changes': <Object?>[
              <String, Object?>{'path': 'lib/updated.dart'},
            ],
          },
        },
        <String, Object?>{
          'id': 'diff-placeholder',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'detailsText': '[]',
          'metadata': <String, Object?>{'changes': <Object?>[]},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Edited 1 file'), findsOneWidget);
    expect(find.text('Edited files'), findsNothing);
  });

  testWidgets('keeps completed file change payloads without structured paths', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'diff-payload',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'detailsText': '@@ -1 +1 @@\n-old\n+new',
          'metadata': <String, Object?>{'changes': <Object?>[]},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Edited files'), findsOneWidget);
  });

  testWidgets('keeps unsuccessful file change outcomes without a payload', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'diff-failed',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'failed',
          'metadata': <String, Object?>{'changes': <Object?>[]},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Edited files'), findsOneWidget);
  });

  testWidgets('keeps waiting after a hidden file change placeholder', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-tools',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'command-visible',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'Ran command',
        },
        <String, Object?>{
          'id': 'diff-placeholder',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'detailsText': '[]',
          'metadata': <String, Object?>{'changes': <Object?>[]},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, settle: false);

    expect(
      find.byKey(const ValueKey<String>('codex-streaming-worked-summary')),
      findsOneWidget,
    );
  });
}
