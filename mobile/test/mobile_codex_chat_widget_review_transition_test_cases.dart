part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewTransitionTests() {
  testWidgets('mobile groups review mode with a dedicated icon', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'review-mode',
          'turnId': 'turn-review',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'Entered review mode',
          'metadata': <String, Object?>{'itemType': 'enteredReviewMode'},
        },
        <String, Object?>{
          'id': 'review-command',
          'turnId': 'turn-review',
          'kind': 'command',
          'status': 'completed',
          'title': 'rg --files',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-review-mode');

    final summary = find.text('Entered review mode, Ran 1 command');
    expect(summary, findsOneWidget);
    await tester.tap(summary);
    await tester.pump();

    expect(find.text('Entered review mode'), findsOneWidget);
    expect(find.byIcon(AleraIcons.review), findsOneWidget);
  });

  testWidgets('mobile groups review activity reconstructed from raw events', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'events': <Object?>[
          <String, Object?>{
            'method': 'item/completed',
            'params': <String, Object?>{
              'turnId': 'turn-review',
              'item': <String, Object?>{
                'id': 'review-mode',
                'type': 'enteredReviewMode',
                'review': 'current changes',
              },
            },
          },
          <String, Object?>{
            'method': 'item/completed',
            'params': <String, Object?>{
              'turnId': 'turn-review',
              'item': <String, Object?>{
                'id': 'review-command',
                'type': 'commandExecution',
                'command': 'rg --files',
              },
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-review-events');

    final summary = find.text('Entered review mode, Ran 1 command');
    expect(summary, findsOneWidget);
    await tester.tap(summary);
    await tester.pump();

    expect(find.text('Entered review mode'), findsOneWidget);
    expect(find.byIcon(AleraIcons.review), findsOneWidget);
  });
}
