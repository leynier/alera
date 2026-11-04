import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatMessageSender? _sender(Map<String, Object?> origin) =>
    agentChatMessageSender(AgentChatItemOrigin.fromJson(origin));

void main() {
  test('a queue entry carries the origin the runtime projected', () {
    final entry = AgentChatQueueEntry.fromJson(<String, Object?>{
      'queueId': 'q1',
      'clientMessageId': 'm1',
      'text': 'Run the nightly checks',
      'createdAt': '2026-10-25T10:01:00Z',
      'origin': <String, Object?>{
        'kind': 'automation',
        'automationId': 'a1',
        'automationName': 'Nightly checks',
        'runId': 'r1',
      },
    });
    expect(entry.origin?.kind, AgentChatItemOriginKind.automation);
    expect(entry.origin?.automationName, 'Nightly checks');
    final plain = AgentChatQueueEntry.fromJson(<String, Object?>{
      'queueId': 'q2',
      'text': 'Mine',
    });
    expect(plain.origin, isNull);
    expect(agentChatMessageSender(plain.origin), isNull);
  });

  test('names automations, pull request watches, agents and guests', () {
    expect(
      _sender(<String, Object?>{
        'kind': 'automation',
        'automationName': 'Nightly checks',
      })?.text,
      'Automation · Nightly checks',
    );
    expect(
      _sender(<String, Object?>{'kind': 'automation'})?.text,
      'Automation',
    );
    expect(
      _sender(<String, Object?>{
        'kind': 'pullRequestWatch',
        'url': 'https://github.com/o/r/pull/42',
        'number': 42,
      })?.text,
      'Pull request #42',
    );
    final agent = _sender(<String, Object?>{
      'kind': 'chatMessage',
      'senderChatId': 'planner',
    });
    expect(agent?.kind, AgentChatMessageSenderKind.agent);
    expect(agent?.text, 'Agent');
    expect(agent?.chatId, 'planner');
    expect(
      _sender(<String, Object?>{'kind': 'guest', 'guestName': 'Ana'})?.text,
      'Guest · Ana',
    );
  });

  test('the person and runtime wakes have no sender', () {
    expect(_sender(<String, Object?>{'kind': 'user'}), isNull);
    expect(
      _sender(<String, Object?>{
        'kind': 'orchestrationWake',
        'taskIds': <Object?>['t1'],
      }),
      isNull,
    );
  });

  test('a guest message is a person, not automated input', () {
    expect(
      AgentChatItemOrigin.fromJson(<String, Object?>{'kind': 'guest'})
          .automated,
      isFalse,
    );
  });
}
