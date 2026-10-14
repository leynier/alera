import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

const String _busyReason =
    'The agent can change once this turn ends and nothing is pending.';

Future<FakeAgentChatClient> _pumpChat(
  WidgetTester tester,
  Map<String, Object?> snapshot, {
  double width = 420,
  Set<String>? capabilities,
}) async {
  final client = FakeAgentChatClient(capabilities: capabilities);
  client.handlers['agentChat.snapshot'] = (_) => snapshot;
  client.handlers['agentChat.configure'] = (_) => <String, Object?>{
    'snapshot': <String, Object?>{...snapshot, 'cursor': 9},
  };
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[
      agentChatProviderRow(
        'codex',
        label: 'Codex',
        runtimeModes: <String>['approval-required', 'full-access'],
        models: <Map<String, Object?>>[
          <String, Object?>{'id': 'gpt-5', 'label': 'GPT-5'},
          <String, Object?>{'id': 'gpt-5-mini', 'label': 'GPT-5 Mini'},
        ],
      ),
      agentChatProviderRow(
        'claudeAgent',
        label: 'Claude',
        models: <Map<String, Object?>>[
          <String, Object?>{'id': 'opus', 'label': 'Opus'},
        ],
      ),
      agentChatProviderRow(
        'cursor',
        label: 'Cursor',
        available: false,
        unavailableReason: 'Sign in to Cursor on the host.',
      ),
    ],
  };
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AgentChatTabView(
            hostId: 'host',
            workspaceId: 'workspace-1',
            chatId: 'chat-1',
            provider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

Map<String, Object?> _withHistory({bool running = false}) => agentChatSnapshot(
  turns: <Map<String, Object?>>[
    agentChatTurn(
      'turn-1',
      status: running ? 'running' : 'completed',
      completedAt: running ? null : '2026-10-12T10:00:04Z',
    ),
  ],
  items: <Map<String, Object?>>[
    agentChatItem('prompt', type: 'user_message', text: 'Fix the build'),
    agentChatItem('answer', text: 'Done.'),
  ],
  session: running
      ? agentChatSession(status: 'running', activeTurnId: 'turn-1')
      : null,
);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('agent-chat-model-chip')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the chip names the model and opens a searchable picker', (
    tester,
  ) async {
    await _pumpChat(tester, agentChatSnapshot());
    // The chip and the ready state both name the model, never its raw id.
    expect(find.text('GPT-5'), findsWidgets);
    expect(find.text('gpt-5'), findsNothing);
    await _openPicker(tester);
    expect(find.text('Search agents and models'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Sign in to Cursor on the host.'), findsWidgets);
    expect(find.text('Open Provider Settings'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'mini');
    await tester.pumpAndSettle();
    expect(find.text('GPT-5 Mini'), findsOneWidget);
    expect(find.text('Opus'), findsNothing);
  });

  testWidgets('another agent on an empty chat switches without asking', (
    tester,
  ) async {
    final client = await _pumpChat(tester, agentChatSnapshot());
    await _openPicker(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('picker-claudeAgent-opus')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch To Claude?'), findsNothing);
    final payload = client.payloadsOf('agentChat.configure').single;
    expect(payload['providerInstanceId'], 'claudeAgent');
    expect(payload['model'], 'opus');
  });

  testWidgets('another agent after the first message asks once', (
    tester,
  ) async {
    final client = await _pumpChat(tester, _withHistory());
    await _openPicker(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('picker-claudeAgent-opus')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch To Claude?'), findsOneWidget);
    expect(client.payloadsOf('agentChat.configure'), isEmpty);
    await tester.tap(find.text('Switch Agent'));
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.configure').single['providerInstanceId'],
      'claudeAgent',
    );
  });

  testWidgets('a model under the same agent never asks', (tester) async {
    final client = await _pumpChat(tester, _withHistory());
    await _openPicker(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('picker-codex-gpt-5-mini')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Switch Agent'), findsNothing);
    final payload = client.payloadsOf('agentChat.configure').single;
    expect(payload['model'], 'gpt-5-mini');
    expect(payload.containsKey('providerInstanceId'), isFalse);
  });

  testWidgets('a busy chat shows other agents with the reason', (tester) async {
    final client = await _pumpChat(tester, _withHistory(running: true));
    await _openPicker(tester);
    expect(find.text(_busyReason), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey<String>('picker-claudeAgent-opus')),
    );
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.configure'), isEmpty);
  });

  testWidgets('Full Access asks before it is turned on', (tester) async {
    final client = await _pumpChat(tester, agentChatSnapshot());
    await tester.tap(find.byTooltip('Chat Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Access'));
    await tester.pumpAndSettle();
    expect(find.text('Turn On Full Access?'), findsOneWidget);
    await tester.tap(find.text('Turn On'));
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.configure').single['runtimeMode'],
      'full-access',
    );
  });

  testWidgets('a narrow phone keeps the chip and Send in view', (tester) async {
    await _pumpChat(tester, agentChatSnapshot(), width: 320);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('agent-chat-model-chip')), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('File Checkpointing shows while off and changes when idle', (
    tester,
  ) async {
    final client = await _pumpChat(
      tester,
      agentChatSnapshot(
        session: agentChatSession(fileCheckpointingSupported: true),
      ),
      capabilities: <String>{'agentChatV1', 'agentChatFileCheckpointsV1'},
    );
    client.handlers['agentChat.fileCheckpoints.configure'] = (_) =>
        <String, Object?>{'snapshot': agentChatSnapshot(cursor: 9)};
    await tester.tap(find.byTooltip('Chat Settings'));
    await tester.pumpAndSettle();
    expect(find.text('File Checkpointing'), findsOneWidget);
    await tester.tap(find.text('File Checkpointing'));
    await tester.pumpAndSettle();
    final payload = client
        .payloadsOf('agentChat.fileCheckpoints.configure')
        .single;
    expect(payload['enabled'], isTrue);
  });

  testWidgets('a pending history change holds Send and keeps the draft', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      agentChatSnapshot(
        pendingNativeOperation: <String, Object?>{
          'operationId': 'op-1',
          'state': 'uncertain',
          'kind': 'rewind',
          'recovery': <String, Object?>{'needsReconciliation': true},
        },
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Next step');
    await tester.pump();
    final send = find.ancestor(
      of: find.byIcon(AleraIcons.send),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Next step',
    );
  });
}
