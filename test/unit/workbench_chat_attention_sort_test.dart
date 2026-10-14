import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:alera/src/features/workbench/application/workbench_agent_activity_sort.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = .utc(2026, 10, 13, 12);

WorkspaceTabRecord _terminal(String id) => WorkspaceTabRecord(
  id: id,
  workspaceId: 'w-1',
  kind: .terminal,
  title: id,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  test('chats alone give a workspace its attention class', () {
    WorkspaceAttention of(ChatWorkspaceAttention chats) => workspaceAttention(
      tabs: const <WorkspaceTabRecord>[],
      agentStatuses: const <String, AgentStatusEntry>{},
      now: _now,
      chats: chats,
    );
    expect(
      of(ChatWorkspaceAttention(needsInput: 1, latestAt: _now)).attentionClass,
      AgentAttentionClass.needsYou,
    );
    expect(
      of(const ChatWorkspaceAttention(failed: 1)).attentionClass,
      AgentAttentionClass.needsYou,
    );
    expect(
      of(const ChatWorkspaceAttention(unread: 1)).attentionClass,
      AgentAttentionClass.done,
    );
    expect(
      of(const ChatWorkspaceAttention(waitingOnTasks: 1)).attentionClass,
      AgentAttentionClass.working,
    );
    expect(
      of(const ChatWorkspaceAttention()).attentionClass,
      AgentAttentionClass.idle,
    );
  });

  test('a waiting chat outranks a working terminal agent', () {
    final tab = _terminal('t-1');
    final attention = workspaceAttention(
      tabs: <WorkspaceTabRecord>[tab],
      agentStatuses: <String, AgentStatusEntry>{
        tab.terminalSessionId: AgentStatusEntry(
          terminalSessionId: tab.terminalSessionId,
          workspaceId: tab.workspaceId,
          tabId: tab.id,
          agentType: .claude,
          state: .working,
          prompt: 'Prompt',
          updatedAt: _now,
          stateStartedAt: _now,
        ),
      },
      now: _now,
      chats: ChatWorkspaceAttention(needsInput: 1, latestAt: _now),
    );
    expect(attention.attentionClass, AgentAttentionClass.needsYou);
  });
}
