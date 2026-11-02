import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('a session carries the Stop of its running turn', () {
    final session = AgentChatSession.fromJson(<String, Object?>{
      'status': 'running',
      'activeTurnId': 't1',
      'stop': <String, Object?>{
        'turnId': 't1',
        'requestedAt': '2026-11-02T10:00:00Z',
      },
    });
    expect(session.stop?.turnId, 't1');
    expect(session.stop?.requestedAt, DateTime.utc(2026, 11, 2, 10));
    expect(session.stopUnresponsive, isFalse);
    final ignored = AgentChatSession.fromJson(<String, Object?>{
      'status': 'running',
      'activeTurnId': 't1',
      'stop': <String, Object?>{
        'turnId': 't1',
        'unresponsiveAt': '2026-11-02T10:00:15Z',
      },
    });
    expect(ignored.stopUnresponsive, isTrue);
    // A Stop of an earlier turn says nothing about the running one.
    final other = AgentChatSession.fromJson(<String, Object?>{
      'activeTurnId': 't2',
      'stop': <String, Object?>{
        'turnId': 't1',
        'unresponsiveAt': '2026-11-02T10:00:15Z',
      },
    });
    expect(other.stopUnresponsive, isFalse);
    expect(AgentChatSession.fromJson(<String, Object?>{}).stop, isNull);
  });

  test('a question kept after a restart is answered by message', () {
    final request = AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'q1',
      'kind': 'tool_user_input',
      'answerBy': 'message',
      'questions': <Object?>[
        <String, Object?>{'id': 'target', 'question': 'Which target?'},
      ],
    });
    expect(request.answerByMessage, isTrue);
    expect(request.isQuestion, isTrue);
    expect(
      AgentChatRequest.fromJson(<String, Object?>{
        'requestId': 'q2',
        'kind': 'tool_user_input',
      }).answerByMessage,
      isFalse,
    );
  });

  test('Force stop needs the runtime capability', () async {
    final lifecycle = _Legacy();
    await expectLater(
      lifecycle.forceStop(
        const AgentChatRef(chatId: 'c', workspaceId: 'w'),
        requestId: 'r',
      ),
      throwsUnsupportedError,
    );
    expect(AgentChatWire.forceStop, 'agentChat.forceStop');
    expect(AgentChatWire.forceStopCapability, 'agentChatForceStopV1');
  });
}

final class _Legacy extends AgentChatLifecycleRepository {}
