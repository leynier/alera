part of 'codex_chat_surface_test.dart';

void _registerCodexChatSurfaceRecoveryTests() {
  testWidgets(
    'keeps history visible and docks rollout recovery as a question',
    (tester) async {
      final client = _SurfaceRuntimeClient(
        recovery: const <String, Object?>{
          'kind': 'missingRollout',
          'message': 'The saved Codex context is no longer available.',
        },
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            settingsControllerProvider.overrideWith(_SurfaceSettings.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 800,
                child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.textContaining('Answer from Codex'), findsOneWidget);
      final recovery = find.byKey(
        const ValueKey<String>('codex-thread-recovery'),
      );
      expect(recovery, findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.text('Continue in a new thread?'), findsOneWidget);
      expect(find.text('Continue In New Thread'), findsOneWidget);
      expect(
        find.textContaining('Earlier messages remain visible'),
        findsOneWidget,
      );
      expect(
        tester.getSize(recovery).width,
        lessThanOrEqualTo(AleraTokens.codexQuestionCardMaxWidth),
      );
      expect(
        tester.getBottomRight(recovery).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('codex-composer-shell')),
              )
              .dy,
        ),
      );
      final composer = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('codex-composer-text-field')),
      );
      expect(composer.enabled, isFalse);

      await tester.tap(find.text('Continue In New Thread'));
      await tester.pump();
      expect(client.recoveryRequests, 1);
    },
  );

  testWidgets('keeps rollout recovery bounded in a short tab', (tester) async {
    final client = _SurfaceRuntimeClient(
      recovery: const <String, Object?>{
        'kind': 'missingRollout',
        'message': 'The saved Codex context is no longer available.',
      },
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 260,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('codex-thread-recovery')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-composer-shell')),
      findsOneWidget,
    );
  });

  testWidgets('resets pending recovery state when the active tab changes', (
    tester,
  ) async {
    final firstRecovery = Completer<void>();
    addTearDown(() {
      if (!firstRecovery.isCompleted) firstRecovery.complete();
    });
    final client = _SurfaceRuntimeClient(
      recovery: const <String, Object?>{
        'kind': 'missingRollout',
        'message': 'The saved Codex context is no longer available.',
      },
      recoveryGate: firstRecovery,
      pendingRequests: const <Object?>[],
    );
    final activeTab = ValueNotifier<String>('codex-tab-1');
    addTearDown(activeTab.dispose);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: ValueListenableBuilder<String>(
                valueListenable: activeTab,
                builder: (context, tabId, _) => CodexChatSurface(
                  workspace: _workspace(),
                  tab: _tab(id: tabId),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    await tester.tap(find.text('Continue In New Thread'));
    await tester.pump();
    expect(client.recoveryRequests, 1);

    activeTab.value = 'codex-tab-2';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Continue In New Thread'));
    await tester.pump();

    expect(client.recoveryRequests, 2);
  });
}
