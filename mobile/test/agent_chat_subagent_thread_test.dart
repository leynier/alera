import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_lineage_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

const Set<String> _capabilities = <String>{
  'agentChatV1',
  AgentChatWire.subagentThreadsCapability,
  AgentChatWire.mergeBackCapability,
};

Map<String, Object?> _call() => agentChatItem(
  'call',
  type: 'collab_agent_tool_call',
  status: 'inProgress',
  normalized: <String, Object?>{
    'input': <String, Object?>{'prompt': 'Count every file in lib'},
    'subagent': <String, Object?>{
      'status': 'running',
      'description': 'Count files',
      'taskId': 'child-thread',
      'model': 'gpt-6-luna',
      'reasoningEffort': 'high',
      'startedAt': '2026-10-12T10:00:00Z',
    },
  },
);

Map<String, Object?> _snapshot() {
  final session = agentChatSession();
  (session['capabilities']! as Map<String, Object?>)['stopSubagent'] = true;
  return <String, Object?>{
    ...agentChatSnapshot(
      turns: <Map<String, Object?>>[agentChatTurn('turn-1')],
      items: <Map<String, Object?>>[
        agentChatItem('prompt', type: 'user_message', text: 'Count files'),
        _call(),
        agentChatItem(
          'child',
          text: 'Live sub-agent note',
          normalized: <String, Object?>{'parentItemId': 'call'},
        ),
        agentChatItem('answer', text: 'Main answer'),
      ],
    ),
    'session': session,
  };
}

Map<String, Object?> _summary(String id, {String? forkedFrom}) =>
    <String, Object?>{
      'chatId': id,
      'workspaceId': 'workspace-1',
      'title': id == 'origin' ? 'Plan the build' : 'Fix the build',
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'status': 'ready',
      'updatedAt': '2026-10-12T10:00:00Z',
      'forkedFromChatId': ?forkedFrom,
    };

FakeAgentChatClient _client() {
  final client = FakeAgentChatClient(capabilities: _capabilities);
  client.handlers['agentChat.snapshot'] = (_) => _snapshot();
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[],
  };
  client.handlers['agentChat.subagent'] = (_) => <String, Object?>{
    'call': _call(),
    'items': <Object?>[
      agentChatItem(
        'older',
        text: 'Older sub-agent note',
        normalized: <String, Object?>{'parentItemId': 'call'},
      ),
    ],
  };
  client.handlers['agentChat.stopSubagent'] = (_) => <String, Object?>{
    'stopped': true,
  };
  client.handlers['agentChat.mergeBack'] = (_) => <String, Object?>{
    'chatId': 'origin',
    'status': 'pending',
  };
  client.handlers['agentChat.list'] = (_) => <String, Object?>{
    'chats': <Object?>[
      _summary('chat-1', forkedFrom: 'origin'),
      _summary('origin'),
    ],
  };
  return client;
}

Future<void> _pump(
  WidgetTester tester,
  FakeAgentChatClient client,
  Widget body,
) async {
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
      ],
      child: MaterialApp(home: Scaffold(body: body)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a sub-agent opens as its own read-only screen', (tester) async {
    final client = _client();
    await _pump(
      tester,
      client,
      const AgentChatTabView(
        hostId: 'host',
        workspaceId: 'workspace-1',
        chatId: 'chat-1',
        provider: 'codex',
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-open-call')),
    );
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.subagent').single['itemId'], 'call');
    expect(find.text('Count every file in lib'), findsOneWidget);
    expect(
      find.textContaining('Live sub-agent note', findRichText: true),
      findsOne,
    );
    expect(
      find.textContaining('Older sub-agent note', findRichText: true),
      findsOne,
    );
    expect(
      find.textContaining('Main answer', findRichText: true),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-bar')),
      findsOneWidget,
    );
    expect(find.text('gpt-6-luna, High'), findsOneWidget);
    expect(find.textContaining('Runs on its own'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-stop')),
    );
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.stopSubagent').single,
      containsPair('itemId', 'call'),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-parent')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-bar')),
      findsNothing,
    );
    expect(find.textContaining('Main answer', findRichText: true), findsOne);
  });

  testWidgets('the lineage sheet lists the fork source and merges back', (
    tester,
  ) async {
    final client = _client();
    await _pump(
      tester,
      client,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showAgentChatLineageSheet(
            context,
            const AgentChatSubagentChat(
              hostId: 'host',
              workspaceId: 'workspace-1',
              chatId: 'chat-1',
            ),
          ),
          child: const Text('Lineage'),
        ),
      ),
    );
    await tester.tap(find.text('Lineage'));
    await tester.pumpAndSettle();
    expect(find.text('Lineage · 1 running'), findsOneWidget);
    expect(find.text('Plan the build'), findsOneWidget);
    expect(find.text('Forked From · Idle'), findsOneWidget);
    expect(find.text('Sub-agent · Running'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-lineage-merge')),
    );
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.mergeBack').single['chatId'], 'chat-1');
  });

  testWidgets('without the capability a sub-agent stays inline', (
    tester,
  ) async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => _snapshot();
    await _pump(
      tester,
      client,
      const AgentChatTabView(
        hostId: 'host',
        workspaceId: 'workspace-1',
        chatId: 'chat-1',
        provider: 'codex',
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-open-call')),
      findsNothing,
    );
  });
}
