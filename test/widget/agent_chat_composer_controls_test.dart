import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<AgentChatProviderInstance> _providers = <AgentChatProviderInstance>[
  AgentChatProviderInstance(
    id: 'codex',
    provider: 'codex',
    label: 'Codex',
    runtimeModes: <AgentChatRuntimeMode>[
      AgentChatRuntimeMode.approvalRequired,
      AgentChatRuntimeMode.fullAccess,
    ],
    models: <AgentChatModelOption>[
      AgentChatModelOption(id: 'gpt-5', label: 'GPT 5', isDefault: true),
      AgentChatModelOption(id: 'gpt-6', label: 'GPT 6'),
    ],
  ),
  AgentChatProviderInstance(
    id: 'claudeAgent',
    provider: 'claudeAgent',
    label: 'Claude',
    models: <AgentChatModelOption>[
      AgentChatModelOption(id: 'opus', label: 'Opus'),
    ],
  ),
  AgentChatProviderInstance(
    id: 'cursor',
    provider: 'cursor',
    label: 'Cursor',
    available: false,
    unavailableReason: 'Sign in to Cursor first.',
  ),
];

AgentChatComposerSettings _settings({
  bool neverSent = true,
  bool canSwitchProvider = true,
  AgentChatCatalogState catalog = AgentChatCatalogState.ready,
}) => AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: const AgentChatSession(
    status: AgentChatSessionStatus.ready,
    model: 'gpt-5',
  ),
  providers: catalog == AgentChatCatalogState.ready
      ? _providers
      : const <AgentChatProviderInstance>[],
  canSwitchProvider: canSwitchProvider,
  configuring: false,
  catalog: catalog,
  neverSent: neverSent,
  switchBlockedReason: canSwitchProvider ? null : agentChatSwitchBusyReason,
);

final class _Recorder {
  final List<(AgentChatSelection, String)> chosen =
      <(AgentChatSelection, String)>[];
  final List<AgentChatConfiguration> configured = <AgentChatConfiguration>[];
  int retries = 0;
  int settingsOpened = 0;
}

Future<_Recorder> _pump(
  WidgetTester tester,
  AgentChatComposerSettings settings, {
  bool busy = false,
  bool compact = false,
}) async {
  final recorder = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: AgentChatComposerControls(
            settings: settings,
            enabled: true,
            busy: busy,
            compact: compact,
            onChoose: (pick, label) => recorder.chosen.add((pick, label)),
            onConfigure: recorder.configured.add,
            onRetryCatalog: () => recorder.retries += 1,
            onOpenProviderSettings: () => recorder.settingsOpened += 1,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return recorder;
}

final Finder _picker = find.byKey(
  const ValueKey<String>('agent-chat-model-picker'),
);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(_picker);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the chip names the model and lists every agent', (tester) async {
    await _pump(tester, _settings());
    expect(find.text('GPT 5'), findsOneWidget);
    await _openPicker(tester);
    // Section headers print the agent's label in capitals.
    expect(find.text('CLAUDE'), findsOneWidget);
    expect(find.text('Opus'), findsOneWidget);
    expect(find.text('Sign in to Cursor first.'), findsOneWidget);
    expect(find.text(agentChatOpenProviderSettingsLabel), findsOneWidget);
  });

  testWidgets('before the first message another agent applies at once', (
    tester,
  ) async {
    final recorder = await _pump(tester, _settings());
    await _openPicker(tester);
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(recorder.chosen.single.$1.providerInstanceId, 'claudeAgent');
    expect(recorder.chosen.single.$1.model, 'opus');
    expect(recorder.chosen.single.$2, 'Opus');
  });

  testWidgets('after the first message another agent confirms the handoff', (
    tester,
  ) async {
    final recorder = await _pump(tester, _settings(neverSent: false));
    await _openPicker(tester);
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(find.text(agentChatSwitchAgentTitle('Claude')), findsOneWidget);
    expect(recorder.chosen, isEmpty);
    await tester.tap(find.text(agentChatSwitchAgentConfirm));
    await tester.pumpAndSettle();
    expect(recorder.chosen.single.$1.providerInstanceId, 'claudeAgent');
  });

  testWidgets('a model of the same agent never asks', (tester) async {
    final recorder = await _pump(tester, _settings(neverSent: false));
    await _openPicker(tester);
    await tester.tap(find.text('GPT 6'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(recorder.chosen.single.$1.model, 'gpt-6');
  });

  testWidgets('while busy other agents are disabled with the reason', (
    tester,
  ) async {
    final recorder = await _pump(
      tester,
      _settings(neverSent: false, canSwitchProvider: false),
      busy: true,
    );
    await _openPicker(tester);
    expect(find.text(agentChatSwitchBusyReason), findsWidgets);
    await tester.tap(find.text(agentChatSwitchBusyReason).first);
    await tester.pumpAndSettle();
    expect(recorder.chosen, isEmpty);
  });

  testWidgets('the picker works from the keyboard and Escape closes it', (
    tester,
  ) async {
    final recorder = await _pump(tester, _settings());
    await _openPicker(tester);
    await tester.enterText(find.byType(TextField), 'opus');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(recorder.chosen.single.$1.model, 'opus');

    await _openPicker(tester);
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a loading catalog keeps the chat labels on a disabled chip', (
    tester,
  ) async {
    await _pump(tester, _settings(catalog: AgentChatCatalogState.loading));
    expect(find.text('GPT 5'), findsNothing);
    expect(find.text('Codex'), findsNothing);
    expect(find.text('gpt-5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(_picker);
    // The loading spinner never settles; two frames show whether it opened.
    await tester.pump();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a failed catalog offers Try Again', (tester) async {
    final recorder = await _pump(
      tester,
      _settings(catalog: AgentChatCatalogState.failed),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-catalog-retry')),
    );
    expect(recorder.retries, 1);
  });

  testWidgets('Full Access asks before it applies', (tester) async {
    final recorder = await _pump(tester, _settings());
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-runtime-mode-chip')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Access'));
    await tester.pumpAndSettle();
    expect(find.text(agentChatFullAccessTitle), findsOneWidget);
    await tester.tap(find.text(agentChatFullAccessConfirm));
    await tester.pumpAndSettle();
    expect(
      recorder.configured.single.runtimeMode,
      AgentChatRuntimeMode.fullAccess,
    );
  });

  testWidgets('a compact composer folds the modes into one overflow', (
    tester,
  ) async {
    final recorder = await _pump(tester, _settings(), compact: true);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-runtime-mode-chip')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-more-controls')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Access'));
    await tester.pumpAndSettle();
    expect(find.text(agentChatFullAccessTitle), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(recorder.configured, isEmpty);
  });
}
