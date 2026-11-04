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
  AgentChatWire.transfersCapability,
};

Map<String, Object?> _transfer(
  String id,
  String kind,
  String source, {
  String status = 'consumed',
  String? itemId,
  String? sourceTurnId,
}) => <String, Object?>{
  'transferId': id,
  'kind': kind,
  'sourceChatId': source,
  'targetChatId': 'chat-1',
  'status': status,
  'createdAt': '2026-10-12T10:00:10Z',
  'itemId': ?itemId,
  'sourceTurnId': ?sourceTurnId,
};

Map<String, Object?> _snapshot() => <String, Object?>{
  ...agentChatSnapshot(
    turns: <Map<String, Object?>>[agentChatTurn('turn-1')],
    items: <Map<String, Object?>>[
      agentChatItem('prompt', type: 'user_message', text: 'Plan it'),
      agentChatItem(
        'call',
        type: 'collab_agent_tool_call',
        normalized: <String, Object?>{
          'subagent': <String, Object?>{
            'status': 'completed',
            'description': 'Count files',
            'model': 'gpt-6-luna',
            'reasoningEffort': 'high',
            'summary': 'Counted 42 files.',
          },
        },
      ),
      agentChatItem('answer', text: 'Planned'),
      agentChatItem(
        'merged',
        type: 'notice',
        turnId: null,
        text: '> User: Try an LRU cache',
        createdAt: '2026-10-12T10:00:20Z',
        normalized: <String, Object?>{
          'mergeBack': <String, Object?>{'status': 'pending'},
        },
      ),
    ],
  ),
  'contextTransfers': <Object?>[
    _transfer('fork', 'fork', 'origin', sourceTurnId: 'turn-1'),
    _transfer(
      'merge',
      'mergeBack',
      'fork-2',
      status: 'pending',
      itemId: 'merged',
    ),
  ],
};

Map<String, Object?> _summary(String id, String title, {String? forkedFrom}) =>
    <String, Object?>{
      'chatId': id,
      'workspaceId': 'workspace-1',
      'title': title,
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'model': 'gpt-5',
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
  client.handlers['agentChat.list'] = (_) => <String, Object?>{
    'chats': <Object?>[
      _summary('chat-1', 'Fix the build', forkedFrom: 'origin'),
      _summary('origin', 'Plan the build'),
      _summary('fork-2', 'Cache experiment', forkedFrom: 'chat-1'),
    ],
  };
  return client;
}

Future<void> _pump(WidgetTester tester, Widget body) async {
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = _client();
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

Finder _sheetText(String text) => find.descendant(
  of: find.byKey(const ValueKey<String>('agent-chat-preview-sheet')),
  matching: find.text(text),
);

void main() {
  testWidgets('transfer rows show in the timeline and preview on long press', (
    tester,
  ) async {
    await _pump(
      tester,
      const AgentChatTabView(
        hostId: 'host',
        workspaceId: 'workspace-1',
        chatId: 'chat-1',
        provider: 'codex',
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-transfer-fork')),
      findsOneWidget,
    );
    expect(find.text('Forked From Plan the build'), findsOneWidget);
    expect(find.text('Merged Back From Cache experiment'), findsOneWidget);
    expect(find.text('Waiting for Next Message'), findsOneWidget);
    expect(
      find.textContaining('Try an LRU cache', findRichText: true),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-transfer-toggle-merge')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Try an LRU cache', findRichText: true),
      findsWidgets,
    );

    await tester.longPress(find.text('Sub-agent: Count files'));
    await tester.pumpAndSettle();
    expect(_sheetText('gpt-6-luna · high'), findsOneWidget);
    expect(_sheetText('Counted 42 files.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Forked From Plan the build'));
    await tester.pumpAndSettle();
    expect(_sheetText('Plan the build'), findsOneWidget);
    expect(_sheetText('Forked From · Delivered'), findsOneWidget);
    expect(_sheetText('gpt-5 · Codex'), findsOneWidget);
  });

  testWidgets('the lineage sheet lists transfers and previews its rows', (
    tester,
  ) async {
    await _pump(
      tester,
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
    expect(find.text('Context Transfers'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-lineage-transfer-merge')),
      findsOneWidget,
    );
    expect(
      find.text('Merged Back From · Waiting for Next Message'),
      findsOneWidget,
    );
    await tester.longPress(
      find.byKey(
        const ValueKey<String>('agent-chat-lineage-chat-origin-forkSource'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_sheetText('Forked From'), findsOneWidget);
    expect(_sheetText('Idle'), findsOneWidget);
  });
}
