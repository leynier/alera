part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileForkAvailabilityTests() {
  for (final completed in [false, true]) {
    testWidgets('mobile Fork availability uses complete history: $completed', (
      tester,
    ) async {
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) {
          if (type != 'codex.thread.open') return null;
          return Future.value(<String, Object?>{
            'threadId': 'thread',
            'historyNextCursor': 'older-active-items',
            'chatFeatures': ['codexForkV1'],
            'snapshot': {
              'hasCompletedTurns': completed,
              'activeTurnId': 'active',
              'timelineCells': [
                {
                  'id': 'active-message',
                  'turnId': 'active',
                  'kind': 'userMessage',
                  'status': 'completed',
                  'markdownText': 'Current request',
                },
              ],
              'pendingRequests': [],
            },
          });
        },
      );
      addTearDown(client.dispose);
      await _pumpScreen(tester, client: client, hostId: 'fork-history');
      await tester.tap(find.byTooltip('Codex Chat Actions'));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Fork Chat'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, completed);
      expect(
        client.calls.where((request) => request.type == 'codex.thread.fork'),
        isEmpty,
      );
    });
  }
  for (final goal in [false, true]) {
    testWidgets('mobile history fork excludes synthetic goal messages: $goal', (
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
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) {
          if (type != 'codex.thread.open') return null;
          return Future.value({
            'threadId': 'thread',
            'chatFeatures': ['codexForkV1'],
            'snapshot': {
              'hasCompletedTurns': true,
              'timelineCells': [cell],
              'pendingRequests': <Object?>[],
            },
          });
        },
      );
      addTearDown(client.dispose);
      await _pumpScreen(tester, client: client, hostId: 'goal-fork-$goal');
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
        client.calls.where((call) => call.type == 'codex.thread.fork'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
