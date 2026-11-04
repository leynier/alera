import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_chat_agent_presence.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:flutter_test/flutter_test.dart';

ChatAttentionEntry _chat(
  String chatId, {
  String workspaceId = 'ws',
  String? parent,
  AgentChatSessionStatus status = AgentChatSessionStatus.ready,
  bool childNeedsInput = false,
}) => ChatAttentionEntry(
  chatId: chatId,
  workspaceId: workspaceId,
  title: 'Chat $chatId',
  updatedAt: DateTime.utc(2026),
  tabId: 'tab-$chatId',
  provider: 'claudeAgent',
  status: status,
  parentChatId: parent,
  openChildTaskCount: childNeedsInput ? 1 : 0,
  childNeedsInput: childNeedsInput,
);

void main() {
  test(
    'chats list as agent rows with each delegated chat under its parent',
    () {
      final rows = chatAgentPresence(<ChatAttentionEntry>[
        _chat('a', childNeedsInput: true),
        _chat('b'),
        _chat('a-child', parent: 'a', status: AgentChatSessionStatus.waiting),
        _chat('elsewhere', workspaceId: 'other', parent: 'a'),
      ]);
      expect(rows.map((row) => (row.chatId, row.depth)), <(String?, int)>[
        ('a', 0),
        ('a-child', 1),
        ('b', 0),
        ('elsewhere', 0),
      ]);
      expect(rows.first.agentType, 'claude');
      expect(rows.first.isChat, isTrue);
      // The parent waits on its task; only the child asks the person.
      expect(rows.first.state, 'working');
      expect(rows[1].state, 'waiting');
      final groups = groupWorkspaceAgentRuns(rows.take(3).toList());
      expect(groups.first.kind, WorkspaceAgentGroupKind.waiting);
      expect(groups.first.runs, hasLength(1));
    },
  );

  test('a chat without a tab is not a row', () {
    final chat = ChatAttentionEntry(
      chatId: 'tabless',
      workspaceId: 'ws',
      title: 'Tabless',
      updatedAt: DateTime.utc(2026),
    );
    expect(chatAgentPresence(<ChatAttentionEntry>[chat]), isEmpty);
  });
}
