import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatItem _item(
  String id,
  String type, {
  String text = '',
  String status = 'completed',
  String? title,
  Map<String, Object?> normalized = const <String, Object?>{},
}) => AgentChatItem.fromJson(<String, Object?>{
  'itemId': id,
  'turnId': 'turn-1',
  'type': type,
  'status': status,
  'title': ?title,
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'text': text,
  'normalized': normalized,
});

AgentChatTurnSection _section(List<AgentChatItem> items) =>
    AgentChatTurnSection.fromItems('turn-1', items, turn: null, working: false);

void main() {
  test('sub-agent items hang under the call that started them', () {
    final section = _section(<AgentChatItem>[
      _item('prompt', 'user_message', text: 'Go'),
      _item(
        'task',
        'dynamic_tool_call',
        title: 'Task',
        normalized: <String, Object?>{
          'toolName': 'Task',
          'input': <String, Object?>{'description': 'Explore the parser'},
          'subagent': <String, Object?>{
            'status': 'completed',
            'summary': 'Found it',
          },
        },
      ),
      _item(
        'child-command',
        'command_execution',
        normalized: <String, Object?>{'command': 'ls', 'parentItemId': 'task'},
      ),
      _item(
        'child-text',
        'assistant_message',
        text: 'Sub-agent notes',
        normalized: <String, Object?>{'parentItemId': 'task'},
      ),
      _item('answer', 'assistant_message', text: 'Main answer'),
    ]);
    expect(section.answers.map((item) => item.id), <String>['answer']);
    final row = section.activity.single as AgentChatSubagentRow;
    expect(row.label, 'Explore the parser');
    expect(row.status, AgentChatSubagentStatus.completed);
    expect(row.summary, 'Found it');
    expect(row.childCount, 2);
    expect(row.rows, hasLength(2));
    expect(row.rows.first, isA<AgentChatActionGroupRow>());
    expect((row.rows.last as AgentChatItemRow).item.id, 'child-text');
    expect(
      AgentChatWorkedAction.fromItem(row.call).label,
      'Ran sub-agent: Explore the parser',
    );
  });

  test('a child whose call is missing stays in the main flow', () {
    final section = _section(<AgentChatItem>[
      _item(
        'orphan',
        'command_execution',
        normalized: <String, Object?>{'command': 'ls', 'parentItemId': 'gone'},
      ),
      _item('answer', 'assistant_message', text: 'Done'),
    ]);
    expect(section.activity.single, isA<AgentChatActionGroupRow>());
  });

  test('a collab call is a sub-agent before the provider reports one', () {
    final call = _item(
      'collab',
      'collab_agent_tool_call',
      status: 'inProgress',
    );
    expect(call.startsSubagent, isTrue);
    expect(call.subagentStatus, AgentChatSubagentStatus.running);
    expect(
      _item('read', 'dynamic_tool_call', title: 'Read').startsSubagent,
      isFalse,
    );
  });

  test('a child that needs input raises its parent only in its own level', () {
    final parent = ChatAttentionEntry(
      chatId: 'parent',
      workspaceId: 'ws',
      title: 'Parent',
      updatedAt: DateTime.utc(2026),
      openChildTaskCount: 1,
      childNeedsInput: true,
    );
    final child = ChatAttentionEntry(
      chatId: 'child',
      workspaceId: 'ws',
      title: 'Child',
      updatedAt: DateTime.utc(2026),
      status: AgentChatSessionStatus.waiting,
      parentChatId: 'parent',
    );
    expect(parent.level, ChatAttentionLevel.needsInput);
    expect(parent.ownLevel, ChatAttentionLevel.waitingOnTasks);
    final tally = chatWorkspaceAttentionOf(<ChatAttentionEntry>[parent, child]);
    expect(tally['ws']!.needsInput, 1);
    expect(tally['ws']!.waitingOnTasks, 1);
    // A child the view does not list still raises its parent.
    expect(
      chatWorkspaceAttentionOf(<ChatAttentionEntry>[parent])['ws']!.needsInput,
      1,
    );
  });

  test('summaries carry the delegating parent chat', () {
    final summary = AgentChatSummary.fromJson(<String, Object?>{
      'chatId': 'child',
      'workspaceId': 'ws',
      'parentChatId': 'parent',
    });
    expect(ChatAttentionEntry.fromSummary(summary).parentChatId, 'parent');
  });
}
