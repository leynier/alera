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
    expect(find.text('Claude Default in Usage'), findsOneWidget);
    expect(find.text('Claude CCS Profiles'), findsOneWidget);
    expect(find.text('Kimi API Key Variable'), findsOneWidget);

    final kimiField = find.descendant(
      of: find.byKey(const ValueKey<String>('kimi-api-key-variable')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(kimiField);
    await tester.pump();
    await tester.enterText(kimiField, 'CUSTOM_KIMI_KEY');
    await tester.testTextInput.receiveAction(.done);
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

  testWidgets('configures Claude Default visibility in Usage independently', (
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

    await tester.tap(find.text('Quotas').first);
    await tester.pump();
    final defaultInUsage = find.text('Claude Default in Usage');
    await tester.ensureVisible(defaultInUsage);
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: defaultInUsage,
      matching: find.byType(SettingsSwitchRow),
    );
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pump(const Duration(milliseconds: 50));

    final settings = container
        .read(settingsControllerProvider)
        .agents
        .quotas
        .forHost('local');
    expect(settings.claudeDefaultEnabled, isTrue);
    expect(settings.claudeDefaultShowInUsage, isFalse);
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

  testWidgets('configures the Usage name and visibility for a CCS profile', (
    tester,
  ) async {
    final quotaSettings = AgentQuotaSettings.defaults.withHost(
      'local',
      const AgentQuotaHostSettings(
        claudeProfiles: <ClaudeQuotaProfileSettings>[
          ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'dev'),
        ],
      ),
    );
    final container = await _pumpSettingsDialog(
      tester,
      initialSettings: AleraSettings.defaults.copyWith(
        agents: AleraSettings.defaults.agents.copyWith(quotas: quotaSettings),
      ),
      extraOverrides: <dynamic>[
        agentQuotaStateProvider.overrideWith(
          (ref) async => AgentQuotaState.empty('local'),
        ),
      ],
    );

    await tester.tap(find.text('Quotas').first);
    await tester.pump();
    expect(find.text('Usage: ccdev'), findsOneWidget);

    final editProfile = find.byIcon(AleraIcons.edit);
    await tester.ensureVisible(editProfile);
    await tester.pumpAndSettle();
    await tester.tap(editProfile);
    await tester.pumpAndSettle();

    final usageName = find.byWidgetPredicate(
      (widget) => widget is AleraTextField && widget.labelText == 'Usage Name',
    );
    await tester.enterText(
      find.descendant(of: usageName, matching: find.byType(TextField)),
      'Engineering',
    );
    await tester.tap(find.text('Show in Usage'));
    await tester.tap(find.text('Save Profile'));
    await tester.pump(const Duration(milliseconds: 50));

    final profile = container
        .read(settingsControllerProvider)
        .agents
        .quotas
        .forHost('local')
        .claudeProfiles
        .single;
    expect(profile.usageDisplayName, 'Engineering');
    expect(profile.showInUsage, isFalse);
    expect(find.text('Not shown in Usage'), findsOneWidget);
  });
}
