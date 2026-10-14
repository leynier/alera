import 'package:alera/src/features/chat_tasks/application/chat_task_parent_activity.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _at = DateTime.utc(2026, 10, 13, 9);

AgentChatTask _task(
  String id,
  AgentChatTaskStatus status, {
  String? parent = 'chat-parent',
  String? child,
  AgentChatTaskAttention attention = AgentChatTaskAttention.none,
}) => AgentChatTask(
  id: id,
  status: status,
  createdAt: _at,
  updatedAt: _at,
  parentChatId: parent,
  childChatId: child ?? 'chat-$id',
  attention: attention,
);

void main() {
  test('each parent counts open, waiting and failed children once', () {
    final waiting = _task(
      'input',
      AgentChatTaskStatus.needsInput,
      attention: AgentChatTaskAttention.needsInput,
    );
    final activities = chatTaskParentActivities(
      open: <AgentChatTask>[
        _task('running', AgentChatTaskStatus.running),
        waiting,
        _task('other', AgentChatTaskStatus.preparing, parent: 'chat-other'),
      ],
      attention: <AgentChatTask>[
        waiting,
        _task(
          'failed',
          AgentChatTaskStatus.failed,
          attention: AgentChatTaskAttention.failed,
        ),
      ],
    );
    expect(
      activities['chat-parent'],
      const ChatTaskParentActivity(open: 2, needsInput: 1, failed: 1),
    );
    expect(activities['chat-parent']!.waitingOnTasks, isTrue);
    expect(activities['chat-parent']!.childNeedsInput, isTrue);
    expect(activities['chat-other'], const ChatTaskParentActivity(open: 1));
  });

  test('tasks a person owns belong to no chat', () {
    final activities = chatTaskParentActivities(
      open: <AgentChatTask>[
        _task('mine', AgentChatTaskStatus.running, parent: null),
      ],
      attention: const <AgentChatTask>[],
    );
    expect(activities, isEmpty);
  });

  test('only children of a parent chat are left to their parent', () {
    final children = chatTaskChildChatIds(<AgentChatTask>[
      _task('a', AgentChatTaskStatus.running, child: 'chat-a'),
      _task('b', AgentChatTaskStatus.running, parent: null, child: 'chat-b'),
    ]);
    expect(children, <String>{'chat-a'});
  });
}
