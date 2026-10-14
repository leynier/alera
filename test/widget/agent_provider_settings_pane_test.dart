import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_hosts.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_pane.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_settings_repository.dart';
import 'command_terminal_test_doubles.dart';

void main() {
  final checkedAt = DateTime.now().subtract(const Duration(minutes: 2));

  List<AgentChatProviderInstance> catalog() => <AgentChatProviderInstance>[
    AgentChatProviderInstance(
      id: 'claudeAgent',
      provider: 'claudeAgent',
      label: 'Claude',
      installed: true,
      version: '2.1.4',
      checkedAt: checkedAt,
      auth: AgentChatProviderAuth(status: .signedIn, checkedAt: checkedAt),
      models: const <AgentChatModelOption>[
        AgentChatModelOption(id: null, label: 'Provider Default'),
        AgentChatModelOption(id: 'opus', label: 'Opus'),
      ],
    ),
    AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'Codex',
      installed: true,
      version: '0.130.0',
      checkedAt: checkedAt,
      setup: const <AgentChatProviderSetupCommand>[
        AgentChatProviderSetupCommand(
          action: 'signIn',
          label: 'Sign In',
          command: 'codex login',
        ),
      ],
    ),
    AgentChatProviderInstance(
      id: 'cursor',
      provider: 'cursor',
      label: 'Cursor',
      installed: false,
      available: false,
      checkedAt: checkedAt,
    ),
    AgentChatProviderInstance(
      id: 'work-claude',
      provider: 'claudeAgent',
      label: 'Work Claude',
      installed: true,
      checkedAt: checkedAt,
      custom: true,
    ),
  ];

  AgentChatProviderInstanceEnvelope workClaude() =>
      AgentChatProviderInstanceEnvelope.fromJson(<String, Object?>{
        'providerInstanceId': 'work-claude',
        'provider': 'claudeAgent',
        'label': 'Work Claude',
        'environment': <Object?>[
          <String, Object?>{
            'name': 'ANTHROPIC_API_KEY',
            'sensitive': true,
            'secretSaved': true,
          },
        ],
      });

  Future<FakeAgentChatSettingsRepository> pumpPane(
    WidgetTester tester, {
    FakeAgentChatSettingsRepository? repository,
    FakeCommandTerminalRuntime? runtime,
    String? initialHostId,
    String? initialProviderInstanceId,
  }) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake =
        repository ??
        FakeAgentChatSettingsRepository(
          revision: 5,
          catalog: catalog(),
          instances: <AgentChatProviderInstanceEnvelope>[workClaude()],
          preferencesValue: const AgentChatPreferences(revision: 2),
        );
    addTearDown(fake.dispose);
    var nextId = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatSettingsRepositoryProvider.overrideWithValue(fake),
          agentChatIdGeneratorProvider.overrideWithValue(
            () => 'request-${++nextId}',
          ),
          agentProviderHostOptionsProvider.overrideWithValue(
            const <AgentProviderHostOption>[
              AgentProviderHostOption(hostId: null, label: 'This Device'),
              AgentProviderHostOption(
                hostId: 'build-mac',
                label: 'Build Mac',
                os: HostOs.macos,
              ),
            ],
          ),
          agentProviderActiveWorkspaceHostProvider.overrideWithValue(null),
          agentProviderProjectsProvider.overrideWithValue(
            const <({String id, String name})>[(id: 'p1', name: 'Alera')],
          ),
          if (runtime != null)
            terminalRuntimeProvider.overrideWithValue(runtime),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 1500,
              height: 2300,
              child: AgentProviderSettingsPane(
                initialHostId: initialHostId,
                initialProviderInstanceId: initialProviderInstanceId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('lists providers with an honest status for each', (tester) async {
    await pumpPane(tester);

    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('Build Mac'), findsOneWidget);
    expect(find.text('Checked 2m ago'), findsOneWidget);
    // Claude has a verified sign-in; Codex is installed but unverified.
    expect(find.text('Ready'), findsWidgets);
    expect(find.text('Unknown Sign-In'), findsWidgets);
    expect(find.text('Not Installed'), findsOneWidget);
    expect(find.text('Signed in  ·  Checked 2m ago'), findsOneWidget);
  });

  testWidgets('the list switch turns a provider off without its launch '
      'definition', (tester) async {
    final fake = await pumpPane(tester);

    final codexRow = find.byKey(const ValueKey<String>('provider-row-codex'));
    await tester.tap(
      find.descendant(of: codexRow, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();

    expect(fake.calls, <String>['upsert codex @5 request-1 host=local']);
    expect(fake.upserts.single.toJson(), <String, Object?>{
      'providerInstanceId': 'codex',
      'provider': 'codex',
      'enabled': false,
    });
  });

  testWidgets('a replaced secret is write-only and saved by itself', (
    tester,
  ) async {
    final fake = await pumpPane(
      tester,
      initialProviderInstanceId: 'work-claude',
    );

    await tester.ensureVisible(find.text('Replace'));
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    final secretField = find.widgetWithText(
      TextField,
      'New value for ANTHROPIC_API_KEY',
    );
    // The value is typed into an obscured field and never echoed.
    expect(tester.widget<TextField>(secretField).obscureText, isTrue);
    await tester.enterText(secretField, 'sk-ant-secret');
    // enterText does not pump; Use Value enables on the next frame.
    await tester.pump();
    await tester.tap(find.text('Use Value'));
    await tester.pumpAndSettle();

    // Handing the value over clears the field, so no text input, label or
    // editable keeps it.
    expect(find.text('sk-ant-secret'), findsNothing);
    expect(find.text('Saved On Save'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.calls, <String>[
      'secret.set work-claude ANTHROPIC_API_KEY @5 request-1 host=local',
    ]);
    expect(fake.secretValues, <String>['sk-ant-secret']);
    expect(fake.upserts, isEmpty);
    expect(find.text('sk-ant-secret'), findsNothing);
  });

  testWidgets('removing an instance in use shows the impact first', (
    tester,
  ) async {
    final fake =
        FakeAgentChatSettingsRepository(
            revision: 5,
            catalog: catalog(),
            instances: <AgentChatProviderInstanceEnvelope>[workClaude()],
          )
          ..impact = const AgentChatProviderRemovalImpact(
            providerInstanceId: 'work-claude',
            count: 1,
            openChats: <AgentChatProviderRemovalChat>[
              AgentChatProviderRemovalChat(
                chatId: 'chat-1',
                title: 'Fix login',
                workspaceId: 'ws-1',
              ),
            ],
          );
    await pumpPane(
      tester,
      repository: fake,
      initialProviderInstanceId: 'work-claude',
    );

    await tester.ensureVisible(find.text('Remove Provider'));
    await tester.tap(find.text('Remove Provider'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Work Claude?'), findsOneWidget);
    expect(find.textContaining('Fix login'), findsOneWidget);
    expect(fake.calls, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(fake.calls, <String>[
      'remove work-claude @5 request-1 allowInUse=true host=local',
    ]);
  });

  testWidgets('Sign In asks the host for the instance recipe, then checks '
      'again', (tester) async {
    final runtime = FakeCommandTerminalRuntime(running: false);
    addTearDown(runtime.dispose);
    final fake = await pumpPane(
      tester,
      runtime: runtime,
      initialProviderInstanceId: 'codex',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();
    // Only the opaque selection leaves the pane; the host resolves the
    // verified command with this instance's own profile.
    final payload = runtime.lastTab!.payload;
    expect(payload[commandTerminalProviderSetupPayloadKey], <String, Object?>{
      'providerInstanceId': 'codex',
      'action': 'signIn',
    });
    expect(payload.containsKey(workspaceTabInitialCommandPayloadKey), isFalse);
    expect(payload.values.toString(), isNot(contains('codex login')));

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(fake.catalogReads.last, (hostId: null, refresh: true));
  });

  testWidgets('a Remote Host shows setup commands without running them', (
    tester,
  ) async {
    final fake = await pumpPane(
      tester,
      initialHostId: 'build-mac',
      initialProviderInstanceId: 'codex',
    );

    expect(fake.catalogReads.first.hostId, 'build-mac');
    final signIn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sign In'),
    );
    expect(signIn.onPressed, isNull);
    expect(find.text('codex login'), findsOneWidget);
  });

  testWidgets('hiding a model writes the instance model preferences', (
    tester,
  ) async {
    final fake = await pumpPane(
      tester,
      initialProviderInstanceId: 'claudeAgent',
    );

    await tester.ensureVisible(find.byTooltip('Hide From Picker').first);
    await tester.tap(find.byTooltip('Hide From Picker').first);
    await tester.pumpAndSettle();

    final update = fake.preferenceUpdates.single.toJson();
    expect(update['expectedRevision'], 2);
    expect((update['operations']! as List<Object?>).single, <String, Object?>{
      'type': 'setModels',
      'providerInstanceId': 'claudeAgent',
      'hidden': <String>['opus'],
      'order': <String>[],
    });
  });

  testWidgets('an older runtime keeps launch settings read-only', (
    tester,
  ) async {
    final fake = FakeAgentChatSettingsRepository(
      catalog: catalog(),
      providerSettings: false,
      preferencesEnabled: false,
    );
    await pumpPane(tester, repository: fake);

    expect(
      find.textContaining('needs an update before provider launch settings'),
      findsOneWidget,
    );
    final codexRow = find.byKey(const ValueKey<String>('provider-row-codex'));
    final toggle = tester.widget<Switch>(
      find.descendant(of: codexRow, matching: find.byType(Switch)),
    );
    expect(toggle.onChanged, isNull);
    expect(fake.calls, isEmpty);
  });
}
