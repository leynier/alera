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
          'metadata': <String, Object?>{
            'itemType': 'fileChange',
            'changes': <Object?>[],
          },
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

  testWidgets(
    'suppresses aggregate turn diffs when structured file changes exist',
    (tester) async {
      final client = _SurfaceRuntimeClient(
        pendingRequests: const <Object?>[],
        timelineCells: const <Object?>[
          <String, Object?>{
            'id': 'diff-turn-tools',
            'turnId': 'turn-tools',
            'kind': 'diff',
            'status': 'completed',
            'detailsText':
                'diff --git a/a/updated.dart b/a/updated.dart\n'
                '+++ b/a/updated.dart\n@@ -1 +1 @@\n-old\n+new',
            'metadata': <String, Object?>{
              'lastDelta': '+new',
              'supersededByStructuredFileChanges': true,
            },
          },
          <String, Object?>{
            'id': 'item-file-change',
            'turnId': 'turn-tools',
            'kind': 'diff',
            'status': 'completed',
            'metadata': <String, Object?>{
              'itemType': 'fileChange',
              'changes': <Object?>[
                <String, Object?>{
                  'path': 'a/updated.dart',
                  'diff': '@@ -1 +1 @@\n-old\n+new',
                },
              ],
            },
          },
        ],
      );
      addTearDown(client.dispose);
      await _pumpTimelineSegmentSurface(tester, client);

      expect(find.text('Edited updated.dart +1 -1'), findsOneWidget);
      expect(find.text('Edited files'), findsNothing);
    },
  );

  testWidgets('keeps aggregate diffs with changes outside structured items', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'diff-turn-tools',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'detailsText':
              'diff --git a/lib/generated.dart b/lib/generated.dart\n'
              '+++ b/lib/generated.dart\n@@ -1 +1 @@\n-old\n+new',
        },
        <String, Object?>{
          'id': 'item-file-change',
          'turnId': 'turn-tools',
          'kind': 'diff',
          'status': 'completed',
          'metadata': <String, Object?>{
            'itemType': 'fileChange',
            'changes': <Object?>[
              <String, Object?>{'path': 'lib/updated.dart'},
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Worked'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('worked-action-group-diff-turn-tools')),
      findsOneWidget,
    );
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
