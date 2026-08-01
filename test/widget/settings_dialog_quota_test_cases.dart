part of 'settings_dialog_test.dart';

void _registerSettingsDialogQuotaTests() {
  testWidgets('shows quotas separately and keeps Claude settings together', (
    tester,
  ) async {
    final container = await _pumpSettingsDialog(
      tester,
      extraOverrides: <dynamic>[
        agentQuotaStateProvider.overrideWith(
          (ref) async => AgentQuotaState.empty('local'),
        ),
      ],
    );

    expect(find.text('Quotas'), findsOneWidget);
    await tester.tap(find.text('Agents').first);
    await tester.pump();
    expect(find.text('Claude Default Quotas'), findsNothing);

    await tester.tap(find.text('Quotas').first);
    await tester.pump();

    expect(find.text('Provider Quotas'), findsWidgets);
    expect(find.text('Claude Code Quotas'), findsOneWidget);
    expect(find.text('Claude Default Quotas'), findsOneWidget);
    expect(find.text('Claude CCS Profiles'), findsOneWidget);
    expect(find.text('Kimi API Key Variable'), findsOneWidget);

    final kimiField = find.descendant(
      of: find.byKey(const ValueKey<String>('kimi-api-key-variable')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(kimiField);
    await tester.pump();
    await tester.enterText(kimiField, 'CUSTOM_KIMI_KEY');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .agents
          .quotas
          .forHost('local')
          .environment
          .kimiApiKey,
      'CUSTOM_KIMI_KEY',
    );
  });

  testWidgets('toggles quota pinning from the settings pane', (tester) async {
    final container = await _pumpSettingsDialog(
      tester,
      extraOverrides: <dynamic>[
        agentQuotaStateProvider.overrideWith(
          (ref) async => AgentQuotaState.empty('local'),
        ),
      ],
    );

    await tester.tap(find.text('Quotas').first);
    await tester.pump();

    // Every provider row plus Claude Default starts pinned.
    expect(find.byTooltip('Shown in status bar'), findsWidgets);
    expect(
      find.byTooltip('Hidden from status bar - available in the quota panel'),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Shown in status bar').first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .agents
          .quotas
          .forHost('local')
          .unpinnedQuotaKeys,
      hasLength(1),
    );
    expect(
      find.byTooltip('Hidden from status bar - available in the quota panel'),
      findsOneWidget,
    );
  });
}
