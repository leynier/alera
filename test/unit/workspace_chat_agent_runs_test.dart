import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/application/workspace_details_agent_groups.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTabRecord _chatTab(String chatId) => WorkspaceTabRecord(
  id: 'tab-$chatId',
  workspaceId: 'ws',
  title: chatId,
  kind: WorkspaceTabKind.agentChat,
  payload: <String, Object?>{'chatId': chatId, 'provider': 'claudeAgent'},
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ChatAttentionEntry _chat(
  String chatId, {
  String? parent,
  AgentChatSessionStatus status = AgentChatSessionStatus.ready,
  bool childNeedsInput = false,
  String provider = 'claudeAgent',
}) => ChatAttentionEntry(
  chatId: chatId,
  workspaceId: 'ws',
  title: 'Chat $chatId',
  updatedAt: DateTime.utc(2026),
  tabId: 'tab-$chatId',
  provider: provider,
  status: status,
  parentChatId: parent,
  openChildTaskCount: childNeedsInput ? 1 : 0,
  childNeedsInput: childNeedsInput,
);

void main() {
  test(
    'each chat keeps its own delegation tree among the workspace agents',
    () {
      final runs = visibleWorkspaceAgentRuns(
        tabs: <WorkspaceTabRecord>[
          _chatTab('a'),
          _chatTab('b'),
          _chatTab('a-child'),
          _chatTab('b-child'),
          _chatTab('a-grandchild'),
        ],
        agentStatuses: const <String, AgentStatusEntry>{},
        chats: <String, ChatAttentionEntry>{
          for (final chat in <ChatAttentionEntry>[
            _chat('a'),
            _chat('b'),
            _chat('a-child', parent: 'a'),
            _chat('b-child', parent: 'b'),
            _chat('a-grandchild', parent: 'a-child', provider: 'muse'),
          ])
            chat.chatId: chat,
        },
      );
      expect(
        runs.map((run) => (run.chat!.chatId, run.chat!.depth)),
        <(String, int)>[
          ('a', 0),
          ('a-child', 1),
          ('a-grandchild', 2),
          ('b', 0),
          ('b-child', 1),
        ],
      );
      expect(runs[2].agentType, isNull);
      expect(runs[2].identityKey, 'chat:muse');
      expect(runs.first.agentType, AgentType.claude);
    },
  );

  test('a child that needs input counts once for the tray badge', () {
    final tabs = <WorkspaceTabRecord>[_chatTab('parent'), _chatTab('child')];
    final count = pendingReviewCountForTabs(
      tabs: tabs,
      agentStatuses: const <String, AgentStatusEntry>{},
      chats: <String, ChatAttentionEntry>{
        'parent': _chat('parent', childNeedsInput: true),
        'child': _chat(
          'child',
          parent: 'parent',
          status: AgentChatSessionStatus.waiting,
        ),
      },
    );
    expect(count, 1);
  });

  test('details keep a delegated chat under its parent when sorting', () {
    final runs = visibleWorkspaceAgentRuns(
      tabs: <WorkspaceTabRecord>[
        _chatTab('idle'),
        _chatTab('idle-child'),
        _chatTab('busy'),
      ],
      agentStatuses: const <String, AgentStatusEntry>{},
      chats: <String, ChatAttentionEntry>{
        'idle': _chat('idle'),
        'idle-child': _chat(
          'idle-child',
          parent: 'idle',
          status: AgentChatSessionStatus.waiting,
        ),
        'busy': _chat('busy', status: AgentChatSessionStatus.running),
      },
    );
    final groups = groupWorkspaceDetailsAgentRuns(
      runs,
      panel: null,
      now: DateTime.utc(2026),
    );
    expect(groups.main.map((run) => run.chat!.chatId), <String>[
      'busy',
      'idle',
      'idle-child',
    ]);
  });
}
