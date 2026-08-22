part of 'codex_chat_surface_test.dart';

void registerCodexTimelineReviewTransitionTests() {
  testWidgets('groups review mode with turn activity using its own icon', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-review',
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
    await _pumpTimelineSegmentSurface(tester, client);

    final summary = find.text('Entered review mode, ran 1 command');
    expect(summary, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('worked-action-group-review-mode'),
        ),
        matching: find.byIcon(AleraIcons.review),
      ),
      findsOneWidget,
    );

    await tester.tap(summary);
    await tester.pump();

    final review = find.byKey(
      const ValueKey<String>('worked-action-review-mode'),
    );
    expect(review, findsOneWidget);
    expect(
      find.descendant(of: review, matching: find.byIcon(AleraIcons.review)),
      findsOneWidget,
    );
  });
}
