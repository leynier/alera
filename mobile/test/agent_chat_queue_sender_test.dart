import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

Map<String, Object?> _queued(
  String id,
  String text, [
  Map<String, Object?>? origin,
]) => <String, Object?>{
  'queueId': id,
  'clientMessageId': 'm-$id',
  'text': text,
  'createdAt': '2026-10-25T10:01:00Z',
  'origin': ?origin,
};

Future<FakeAgentChatClient> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = FakeAgentChatClient(
    capabilities: <String>{
      AgentChatWire.capability,
      AgentChatWire.queueEditCapability,
      AgentChatWire.queueReorderCapability,
    },
  );
  client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
    session: agentChatSession(status: 'waiting', activeTurnId: 'turn-1'),
    turns: <Map<String, Object?>>[
      agentChatTurn('turn-1', status: 'running', completedAt: null),
    ],
    queue: <Map<String, Object?>>[
      _queued('q1', 'Mine'),
      _queued('q2', 'Run checks', <String, Object?>{
        'kind': 'automation',
        'automationName': 'Nightly checks',
      }),
      _queued('q3', 'Review this', <String, Object?>{
        'kind': 'chatMessage',
        'senderChatId': 'planner-chat',
      }),
    ],
  );
  client.handlers['agentChat.queueEdit'] = (_) => <String, Object?>{
    'updated': true,
    'queueId': 'q1',
  };
  client.handlers['agentChat.queueReorder'] = (payload) => <String, Object?>{
    'reordered': true,
    'queueId': payload['queueId'],
    'index': payload['index'],
  };
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  addTearDown(client.disconnect);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
        mobileChatTasksSupportedProvider('host')
            .overrideWith((ref) async => false),
        mobileChatTaskChatProvider('host', 'planner-chat').overrideWith(
          (ref) async => AgentChatDirectoryEntry(
            chat: AgentChatSummary(
              chatId: 'planner-chat',
              workspaceId: 'workspace-2',
              title: 'Planner',
              provider: 'codex',
              providerInstanceId: 'codex',
              status: AgentChatSessionStatus.ready,
              updatedAt: DateTime.utc(2026, 10, 25),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const Scaffold(
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

Finder _sender(String queueId) =>
    find.byKey(ValueKey<String>('queue-sender-$queueId'));

void main() {
  testWidgets('queued messages name an automation and an agent sender', (
    tester,
  ) async {
    await _pump(tester);
    expect(_sender('q1'), findsNothing);
    expect(
      find.descendant(
        of: _sender('q2'),
        matching: find.text('Automation · Nightly checks'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _sender('q3'),
        matching: find.text('Agent · Planner'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _sender('q3'),
        matching: find.byKey(const ValueKey<String>('queue-sender-open-chat')),
      ),
      findsOneWidget,
    );
  });
}
