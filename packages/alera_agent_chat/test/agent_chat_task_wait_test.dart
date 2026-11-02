import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 11);

AgentChatItem _call(
  String id, {
  String? toolName,
  String? server,
  Object? input,
  AgentChatItemType type = AgentChatItemType.mcpToolCall,
  AgentChatItemStatus status = AgentChatItemStatus.inProgress,
  String turnId = 'turn',
}) => AgentChatItem(
  id: id,
  type: type,
  status: status,
  createdAt: _at,
  updatedAt: _at,
  turnId: turnId,
  toolName: toolName,
  server: server,
  input: input,
);

AgentChatChange _change(List<AgentChatItem> items, {String? turn = 'turn'}) =>
    AgentChatChange(
      chatId: 'chat',
      cursor: 1,
      items: items,
      session: AgentChatSession(
        status: AgentChatSessionStatus.running,
        activeTurnId: turn,
      ),
    );

void main() {
  test('task waits are found under every provider naming', () {
    for (final item in <AgentChatItem>[
      _call('claude', toolName: 'mcp__alera__chat_task_wait'),
      _call('codex', toolName: 'chat_task_wait', server: 'alera'),
      _call('acp', toolName: 'alera_chat_task_wait'),
      _call(
        'cursor',
        toolName: 'mcp',
        input: <String, Object?>{
          'providerIdentifier': 'alera',
          'toolName': 'chat_task_wait',
        },
      ),
      _call(
        'delegate',
        toolName: 'mcp__alera__chat_delegate',
        input: <String, Object?>{'mode': 'wait'},
      ),
    ]) {
      expect(agentChatIsTaskWaitCall(item), isTrue, reason: item.id);
    }
    expect(
      agentChatIsTaskWaitCall(
        _call('async', toolName: 'mcp__alera__chat_delegate'),
      ),
      isFalse,
    );
    expect(
      agentChatIsTaskWaitCall(_call('other', toolName: 'chat_task_wait')),
      isFalse,
    );
  });

  test('a running turn is blocked only when every running call waits', () {
    const session = AgentChatSession(
      status: AgentChatSessionStatus.running,
      activeTurnId: 'turn',
    );
    final wait = _call('wait', toolName: 'mcp__alera__chat_task_wait');
    final command = _call('build', type: AgentChatItemType.commandExecution);
    expect(agentChatBlockedOnTaskWait(session, <AgentChatItem>[wait]), isTrue);
    expect(
      agentChatBlockedOnTaskWait(session, <AgentChatItem>[wait, command]),
      isFalse,
    );
    expect(agentChatBlockedOnTaskWait(session, <AgentChatItem>[]), isFalse);
    expect(
      agentChatBlockedOnTaskWait(const AgentChatSession(), <AgentChatItem>[
        wait,
      ]),
      isFalse,
    );
  });

  test('the fold follows item deltas and forgets an ended turn', () {
    final fold = AgentChatTaskWaitFold();
    final wait = _call('wait', toolName: 'mcp__alera__chat_task_wait');
    expect(fold.apply(_change(<AgentChatItem>[wait])), isTrue);
    expect(fold.blocked('chat'), isTrue);
    expect(
      fold.apply(
        _change(<AgentChatItem>[
          _call(
            'wait',
            toolName: 'mcp__alera__chat_task_wait',
            status: AgentChatItemStatus.completed,
          ),
        ]),
      ),
      isTrue,
    );
    expect(fold.blocked('chat'), isFalse);
    fold.apply(_change(<AgentChatItem>[wait]));
    fold.apply(_change(const <AgentChatItem>[], turn: null));
    expect(fold.blocked('chat'), isFalse);
  });

  test('a blocked running chat reads as waiting, and its work level stays', () {
    final entry = ChatAttentionEntry(
      chatId: 'chat',
      workspaceId: 'ws',
      title: 'Planner',
      updatedAt: _at,
      status: AgentChatSessionStatus.running,
      blockedOnTaskWait: true,
    );
    expect(entry.level, ChatAttentionLevel.waitingOnTasks);
    expect(entry.workLevel, ChatAttentionLevel.working);
    expect(
      entry.withBlockedOnTaskWait(false).level,
      ChatAttentionLevel.working,
    );
    expect(
      chatAttentionWaitingChatIds(<String, ChatAttentionEntry>{
        'chat': entry,
        'other': entry.withBlockedOnTaskWait(false),
      }),
      <String>{'chat'},
    );
  });
}
