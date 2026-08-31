part of 'codex_chat_surface_test.dart';

void _registerCodexForkAvailabilityTests() {
  for (final completed in [false, true]) {
    testWidgets('Fork availability uses complete history: $completed', (
      tester,
    ) async {
      final client = _SurfaceRuntimeClient(
        supportsSessions: true,
        hasCompletedTurns: completed,
        historyNextCursor: 'older-active-items',
        activeTurnId: 'active',
        pendingRequests: [],
        timelineCells: [
          {
            'id': 'active-message',
            'turnId': 'active',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Current request',
          },
        ],
      );
      addTearDown(client.dispose);
      await _pumpComposerSurface(tester, client);
      await tester.tap(find.byTooltip('Add Photos And Files'));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Fork Chat'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, completed);
      expect(
        client.requests.where((request) => request.type == 'codex.thread.fork'),
        isEmpty,
      );
    });
  }
  for (final goal in [false, true]) {
    testWidgets('history fork excludes synthetic goal messages: $goal', (
      tester,
    ) async {
      final cell = <String, Object?>{
        'id': 'message',
        'turnId': goal ? 'goal-client' : 'native-turn',
        'kind': 'userMessage',
        'status': 'completed',
        'markdownText': 'Saved request',
        'metadata': {'isGoal': goal},
      };
      final client = _SurfaceRuntimeClient(
        supportsSessions: true,
        hasCompletedTurns: true,
        pendingRequests: [],
        timelineCells: [cell],
      );
      addTearDown(client.dispose);
      await _pumpComposerSurface(tester, client);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.text('Saved request')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('History Actions'));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Fork From Here'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, !goal);
      expect(
        client.requests.where((call) => call.type == 'codex.thread.fork'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
