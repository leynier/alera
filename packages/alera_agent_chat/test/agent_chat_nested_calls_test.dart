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

AgentChatItem _tool(
  String id,
  String tool, {
  String? caller,
  String status = 'completed',
}) => _item(
  id,
  'dynamic_tool_call',
  title: tool,
  status: status,
  normalized: <String, Object?>{'toolName': tool, 'parentItemId': ?caller},
);

AgentChatTurnSection _section(List<AgentChatItem> items) =>
    AgentChatTurnSection.fromItems('turn-1', items, turn: null, working: false);

void main() {
  test('calls a tool made through another tool sit under their caller', () {
    final section = _section(<AgentChatItem>[
      _item('prompt', 'user_message', text: 'Go'),
      _tool('code', 'codemode'),
      _tool('code/1', 'read', caller: 'code', status: 'failed'),
      _tool('code/2', 'grep', caller: 'code'),
      _item(
        'after',
        'command_execution',
        normalized: <String, Object?>{'command': 'ls'},
      ),
      _item('answer', 'assistant_message', text: 'Done'),
    ]);
    expect(section.answers.map((item) => item.id), <String>['answer']);
    // The caller stays an ordinary action, not a sub-agent row.
    final group = section.activity.single as AgentChatActionGroupRow;
    expect(group.actions.map((action) => action.item.id), <String>[
      'code',
      'after',
    ]);
    final caller = group.actions.first;
    expect(caller.kind, AgentChatWorkedActionKind.tool);
    expect(caller.label, 'Used codemode');
    expect(caller.nested.map((action) => action.item.id), <String>[
      'code/1',
      'code/2',
    ]);
    expect(caller.nested.first.kind, AgentChatWorkedActionKind.read);
    expect(caller.nested.first.item.isFailed, isTrue);
    expect(group.actions.last.nested, isEmpty);
  });

  test('nested calls nest at any depth', () {
    final section = _section(<AgentChatItem>[
      _tool('outer', 'codemode'),
      _tool('inner', 'codemode', caller: 'outer'),
      _tool('leaf', 'read', caller: 'inner'),
    ]);
    final group = section.activity.single as AgentChatActionGroupRow;
    final outer = group.actions.single;
    expect(outer.nested.single.item.id, 'inner');
    expect(outer.nested.single.nested.single.item.id, 'leaf');
  });

  test('a call whose caller is missing or loops back stays in view', () {
    final section = _section(<AgentChatItem>[
      _tool('orphan', 'read', caller: 'gone'),
      _tool('a', 'read', caller: 'b'),
      _tool('b', 'read', caller: 'a'),
    ]);
    final group = section.activity.single as AgentChatActionGroupRow;
    expect(group.actions.map((action) => action.item.id), <String>[
      'orphan',
      'a',
      'b',
    ]);
  });

  test('a sub-agent call keeps its work as a sub-agent', () {
    final section = _section(<AgentChatItem>[
      _item(
        'task',
        'dynamic_tool_call',
        title: 'Task',
        normalized: <String, Object?>{
          'toolName': 'Task',
          'subagent': <String, Object?>{'status': 'running'},
        },
      ),
      _tool('code', 'codemode', caller: 'task'),
      _tool('code/1', 'read', caller: 'code'),
    ]);
    final row = section.activity.single as AgentChatSubagentRow;
    final group = row.rows.single as AgentChatActionGroupRow;
    expect(group.actions.single.item.id, 'code');
    expect(group.actions.single.nested.single.item.id, 'code/1');
  });
}
