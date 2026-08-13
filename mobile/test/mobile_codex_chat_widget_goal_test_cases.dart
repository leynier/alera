part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexGoalTests() {
  testWidgets('mobile handles goal commands instead of steering', (
    tester,
  ) async {
    var goal = _mobileWidgetGoal();
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal',
      initialSnapshot: <String, Object?>{
        'activeTurnId': 'turn-active',
        'goal': goal,
        'timelineCells': const <Object?>[],
      },
      requestHandler: (type, payload) {
        if (type == 'codex.goal.get') {
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'goal': goal,
          });
        }
        if (type == 'codex.goal.set') {
          goal = <String, Object?>{
            ...goal,
            if (payload['objective'] != null) 'objective': payload['objective'],
            if (payload['status'] != null) 'status': payload['status'],
          };
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'goal': goal,
          });
        }
        return null;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-goal-steer');
    await tester.pump(const Duration(milliseconds: 100));

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/goal pause');
    await tester.pump();
    expect(find.byTooltip('Steer'), findsOneWidget);
    await tester.tap(find.byTooltip('Steer'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.turn.steer'),
      isEmpty,
    );
    final update = client.calls.lastWhere(
      (call) => call.type == 'codex.goal.set',
    );
    expect(update.payload['status'], 'paused');
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
  });

  testWidgets('mobile typed goal updates without clearing accounting', (
    tester,
  ) async {
    Map<String, Object?>? goal = _mobileWidgetGoal(status: 'budgetLimited');
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal',
      initialSnapshot: <String, Object?>{
        'goal': goal,
        'timelineCells': const <Object?>[],
      },
      requestHandler: (type, payload) {
        if (type == 'codex.goal.get') {
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'goal': goal,
          });
        }
        if (type == 'codex.goal.set') {
          goal = <String, Object?>{
            ...goal!,
            'objective': payload['objective']!.toString(),
            'status': payload['status']!.toString(),
          };
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'goal': goal,
          });
        }
        return null;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-goal-replace');
    await tester.pump(const Duration(milliseconds: 100));

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/goal Ship the next release');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final callTypes = client.calls.map((call) => call.type).toList();
    expect(callTypes, isNot(contains('codex.goal.clear')));
    expect(callTypes, contains('codex.goal.set'));
    expect(goal?['objective'], 'Ship the next release');
    expect(goal?['tokensUsed'], 100);
    expect(goal?['timeUsedSeconds'], 300);
    expect(goal?['status'], 'active');
  });

  testWidgets('mobile preserves goal commands on older runtimes', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(initialThreadId: 'thread-legacy');
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-goal-legacy');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/goal Ship the release');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      '/goal Ship the release',
    );
    expect(
      client.calls.where((call) => call.type.startsWith('codex.goal.')),
      isEmpty,
    );
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
  });

  testWidgets('mobile hides stale goals from older runtimes', (tester) async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-legacy',
      initialSnapshot: <String, Object?>{
        'goal': _mobileWidgetGoal(),
        'timelineCells': const <Object?>[],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stale-goal');
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey<String>('mobile-codex-goal-bar')),
      findsNothing,
    );
  });
}

Map<String, Object?> _mobileWidgetGoal({
  String objective = 'Ship the release',
  String status = 'active',
}) => <String, Object?>{
  'threadId': 'thread-goal',
  'objective': objective,
  'status': status,
  'tokenBudget': null,
  'tokensUsed': status == 'budgetLimited' ? 100 : 0,
  'timeUsedSeconds': status == 'budgetLimited' ? 300 : 0,
  'createdAt': 1,
  'updatedAt': 2,
};
