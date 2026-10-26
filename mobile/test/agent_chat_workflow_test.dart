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
  AgentChatWire.workflowsCapability,
};

Map<String, Object?> _call() => agentChatItem(
  'call',
  type: 'dynamic_tool_call',
  status: 'completed',
  normalized: <String, Object?>{
    'toolName': 'Workflow',
    'subagent': <String, Object?>{
      'status': 'running',
      'taskId': 'wf',
      'taskType': 'local_workflow',
      'startedAt': '2026-10-12T10:00:00Z',
      'workflow': <String, Object?>{
        'name': 'probe-wf',
        'runHandles': <String, Object?>{'scriptPath': '/p/run.js'},
        'phases': <Object?>[
          <String, Object?>{'index': 1, 'title': 'Alpha'},
        ],
        'agents': <Object?>[
          <String, Object?>{
            'index': 1,
            'label': 'alpha:one',
            'state': 'running',
            'agentId': 'a1',
            'phaseIndex': 1,
            'prompt': 'Reply with exactly: A1',
          },
          <String, Object?>{
            'index': 2,
            'label': 'alpha:two',
            'state': 'completed',
            'phaseIndex': 1,
            'result': 'A2',
          },
        ],
        'totalTokens': 71141,
      },
    },
  },
);

FakeAgentChatClient _client() {
  final client = FakeAgentChatClient(capabilities: _capabilities);
  final session = agentChatSession();
  (session['capabilities']! as Map<String, Object?>)['stopSubagent'] = true;
  client.handlers['agentChat.snapshot'] = (_) => <String, Object?>{
    ...agentChatSnapshot(
      turns: <Map<String, Object?>>[agentChatTurn('turn-1')],
      items: <Map<String, Object?>>[
        agentChatItem('prompt', type: 'user_message', text: 'Run the probe'),
        _call(),
      ],
    ),
    'session': session,
  };
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[],
  };
  client.handlers['agentChat.subagent'] = (_) => <String, Object?>{
    'call': _call(),
    'items': <Object?>[],
  };
  client.handlers['agentChat.workflowScript'] = (_) => <String, Object?>{
    'scriptPath': '/claude/projects/p/run.js',
    'contents': 'export const meta = {name: "probe-wf"};',
    'truncated': true,
  };
  client.handlers['agentChat.workflowAgent'] = (_) => <String, Object?>{
    'answers': <Object?>['The full answer of alpha one'],
  };
  client.handlers['agentChat.list'] = (_) => <String, Object?>{
    'chats': <Object?>[],
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

const Widget _tab = AgentChatTabView(
  hostId: 'host',
  workspaceId: 'workspace-1',
  chatId: 'chat-1',
  provider: 'claudeAgent',
);

void main() {
  testWidgets('the turn row names the workflow and unfolds its phases', (
    tester,
  ) async {
    await _pump(tester, _client(), _tab);
    expect(find.text('Workflow: probe-wf'), findsOneWidget);
    expect(find.text('1 working'), findsOneWidget);
    await tester.tap(find.text('Workflow: probe-wf'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('1/2 agents'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-workflow-member-2')),
    );
    await tester.pumpAndSettle();
    // A member without an id has no transcript; its excerpt shows.
    expect(find.text('Partial answer from workflow progress'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('an opened workflow shows its script and member answers', (
    tester,
  ) async {
    final client = _client();
    await _pump(tester, client, _tab);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-open-call')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-workflow-section-call')),
      findsOneWidget,
    );
    expect(find.text('71k tokens'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-workflow-view-script')),
    );
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.workflowScript').single['itemId'],
      'call',
    );
    expect(
      find.text('export const meta = {name: "probe-wf"};'),
      findsOneWidget,
    );
    expect(
      find.text('Only the first 256 KiB of the script shows.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-workflow-member-1')),
    );
    await tester.pumpAndSettle();
    final asked = client.payloadsOf('agentChat.workflowAgent').single;
    expect(asked['itemId'], 'call');
    expect(asked['agentIndex'], 1);
    expect(find.text('Reply with exactly: A1'), findsOneWidget);
    expect(
      find.textContaining('The full answer of alpha one', findRichText: true),
      findsOne,
    );
  });

  testWidgets('the lineage sheet names the workflow', (tester) async {
    await _pump(
      tester,
      _client(),
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
    expect(find.text('probe-wf'), findsOneWidget);
    expect(find.text('Workflow · 1 working'), findsOneWidget);
  });
}
