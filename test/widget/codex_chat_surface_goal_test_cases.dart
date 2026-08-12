part of 'codex_chat_surface_test.dart';

void _registerCodexChatSurfaceGoalTests() {
  Map<String, Object?> goal({String status = 'active'}) => <String, Object?>{
    'threadId': 'thread-goal',
    'objective': 'Keep the release checks green',
    'status': status,
    'tokenBudget': null,
    'tokensUsed': 12,
    'timeUsedSeconds': 186,
    'createdAt': 1,
    'updatedAt': 2,
  };

  test('equivalent goal snapshots compare by value', () {
    expect(
      CodexThreadGoal.fromJson(goal()),
      CodexThreadGoal.fromJson(goal()),
      reason: 'equivalent snapshots should not rebuild the footer',
    );
  });

  testWidgets('goal bar overlaps the composer and exposes goal actions', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      supportsSessions: true,
      goal: goal(),
      activeTurnId: 'turn-active',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'goal-message',
          'kind': 'userMessage',
          'status': 'completed',
          'createdAt': '2026-08-12T00:00:00Z',
          'updatedAt': '2026-08-12T00:00:00Z',
          'markdownText': 'Keep the release checks green',
          'metadata': <String, Object?>{'isGoal': true},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );
    expect(
      container.read(codexChatControllerProvider('codex-tab')).snapshot.goal,
      isNotNull,
    );
    final bar = tester.getRect(
      find.byKey(const ValueKey<String>('codex-goal-bar')),
    );
    final composer = tester.getRect(
      find.byKey(const ValueKey<String>('codex-composer-shell')),
    );
    expect(bar.left, greaterThan(composer.left));
    expect(bar.right, lessThan(composer.right));
    expect(bar.top, lessThan(composer.top));
    expect(bar.bottom, greaterThan(composer.top));
    expect(find.text('Pursuing goal'), findsOneWidget);
    expect(find.text('• 3m 6s'), findsOneWidget);
    expect(find.text('Sent as goal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-goal-edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-goal-pause-resume')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-goal-clear')),
      findsOneWidget,
    );
  });

  testWidgets('typed goal creates a goal without starting a normal turn', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(supportsGoals: true);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );
    expect(
      container.read(codexChatControllerProvider('codex-tab')).supportsGoals,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('codex-composer-text-field')),
      '/goal Ship the release',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(
      client.goalPayloads,
      hasLength(1),
      reason: 'requests: ${client.requestTypes}',
    );
    expect(client.goalPayloads.single['objective'], 'Ship the release');
    expect(client.goalPayloads.single['recordUserMessage'], isTrue);
    expect(client.requestTypes, isNot(contains('codex.turn.start')));
  });

  testWidgets('desktop disables goals after an unsupported initial set', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      goalSetFailures: 1,
      goalSetFailureMessage: 'Method not found (-32601)',
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('codex-composer-text-field')),
      '/goal Ship the release',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(codexChatControllerProvider('codex-tab')).supportsGoals,
      isFalse,
    );
    expect(find.byKey(const ValueKey<String>('codex-goal-bar')), findsNothing);
  });

  testWidgets('desktop preserves unsupported goal commands as drafts', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient();
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);

    final composer = find.byKey(
      const ValueKey<String>('codex-composer-text-field'),
    );
    await tester.enterText(composer, '/goal Ship the release');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      '/goal Ship the release',
    );
    expect(
      client.requestTypes.where((type) => type.startsWith('codex.goal.')),
      isEmpty,
    );
    expect(client.requestTypes, isNot(contains('codex.turn.start')));
  });

  testWidgets('desktop hides stale goals from unsupported runtimes', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(goal: goal());
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey<String>('codex-goal-bar')), findsNothing);
    final composer = tester.getRect(
      find.byKey(const ValueKey<String>('codex-composer-shell')),
    );
    expect(composer.top, greaterThanOrEqualTo(0));
  });

  testWidgets(
    'typed goal updates an existing goal without clearing accounting',
    (tester) async {
      final client = _SurfaceRuntimeClient(
        supportsGoals: true,
        goal: goal(status: 'budgetLimited'),
      );
      addTearDown(client.dispose);
      await _pumpComposerSurface(tester, client);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(CodexChatSurface)),
        ).read(codexChatControllerProvider('codex-tab')).snapshot.goal,
        isNotNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('codex-composer-text-field')),
        '/goal Ship the next release',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('composer-action-button')),
      );
      await tester.pumpAndSettle();

      expect(client.requestTypes, isNot(contains('codex.goal.clear')));
      expect(client.goal?['tokensUsed'], 12);
      expect(client.goal?['timeUsedSeconds'], 186);
      expect(client.goal?['status'], 'active');
    },
  );

  testWidgets('desktop retries goal discovery when Codex becomes ready', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      supportsSessions: true,
      goal: goal(),
      includeGoalInOpenSnapshot: false,
      goalGetFailures: 1,
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );

    expect(
      container.read(codexChatControllerProvider('codex-tab')).supportsGoals,
      isTrue,
    );
    expect(find.byKey(const ValueKey<String>('codex-goal-bar')), findsNothing);

    client.emit(
      const RuntimeHostEvent('codexServerChanged', <String, Object?>{
        'status': 'ready',
      }),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(codexChatControllerProvider('codex-tab')).snapshot.goal,
      isNotNull,
      reason: '${client.requestTypes}',
    );
    expect(
      find.byKey(const ValueKey<String>('codex-goal-bar')),
      findsOneWidget,
      reason: '${client.requestTypes}',
    );
  });

  testWidgets('desktop hides goals when Codex does not implement the API', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      supportsSessions: true,
      goal: goal(),
      includeGoalInOpenSnapshot: false,
      goalGetFailures: 1,
      goalGetFailureMessage: 'Method not found (-32601)',
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );

    expect(
      container.read(codexChatControllerProvider('codex-tab')).supportsGoals,
      isFalse,
    );
    expect(find.byKey(const ValueKey<String>('codex-goal-bar')), findsNothing);

    client.emit(
      const RuntimeHostEvent('codexServerChanged', <String, Object?>{
        'status': 'ready',
      }),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(codexChatControllerProvider('codex-tab')).supportsGoals,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-goal-bar')),
      findsOneWidget,
    );
  });

  testWidgets('desktop hides goals when Codex disables the feature', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      supportsSessions: true,
      goal: goal(),
      includeGoalInOpenSnapshot: false,
      goalGetFailures: 2,
      goalGetFailureMessage: 'Goals feature is disabled',
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );

    expect(
      container.read(codexChatControllerProvider('codex-tab')).supportsGoals,
      isFalse,
    );
    expect(find.byKey(const ValueKey<String>('codex-goal-bar')), findsNothing);
  });

  testWidgets('failed typed replacement preserves the previous goal', (
    tester,
  ) async {
    final previousGoal = <String, Object?>{
      ...goal(status: 'paused'),
      'threadId': 'thread-current',
    };
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      supportsSessions: true,
      goal: previousGoal,
      goalSetFailures: 1,
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
      find.byKey(const ValueKey<String>('codex-composer-text-field')),
      '/goal Ship the next release',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    final state = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    ).read(codexChatControllerProvider('codex-tab'));
    expect(state.snapshot.goal?.objective, 'Keep the release checks green');
    expect(state.snapshot.goal?.status, CodexThreadGoalStatus.paused);
    expect(state.snapshot.goal?.tokensUsed, 12);
    expect(client.goalPayloads, hasLength(1));
    expect(client.goalPayloads.single['objective'], 'Ship the next release');
    expect(client.requestTypes, isNot(contains('codex.goal.clear')));
  });

  testWidgets('goal edit dialog matches the saved objective flow', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsGoals: true,
      supportsSessions: true,
      goal: goal(status: 'paused'),
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);

    await tester.tap(find.byKey(const ValueKey<String>('codex-goal-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Goal'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('codex-goal-save')),
    );
    expect(save.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('codex-goal-objective-field')),
      'Keep every release check green',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('codex-goal-save')));
    await tester.pumpAndSettle();

    expect(
      client.goalPayloads.last['objective'],
      'Keep every release check green',
    );
    expect(client.goalPayloads.last['status'], 'paused');
  });
}
