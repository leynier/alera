part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexFileChangeTests() {
  testWidgets(
    'mobile suppresses aggregate turn diffs when structured changes exist',
    (tester) async {
      final client = FakeMobileCodexClient(
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
              'changes': '[{"path":"a/updated.dart"}]',
            },
          },
        ],
      );
      addTearDown(client.dispose);
      await _pumpScreen(tester, client: client, hostId: 'host-file-change');

      expect(find.text('Edited Files'), findsOneWidget);
      expect(find.text('Edited 2 files'), findsNothing);
    },
  );

  testWidgets('mobile keeps aggregate changes outside structured file items', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
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
    await _pumpScreen(tester, client: client, hostId: 'host-extra-file-change');

    expect(find.text('Edited 2 files'), findsOneWidget);
  });
}
