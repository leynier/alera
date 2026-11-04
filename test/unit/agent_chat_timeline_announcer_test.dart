import 'package:alera/src/features/agent_chat/application/agent_chat_timeline_sessions.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_announcer.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatTimelineProjection _projection({
  bool running = false,
  String? turnStatus,
  List<Map<String, Object?>> requests = const <Map<String, Object?>>[],
}) => AgentChatTimelineProjection.build(
  AgentChatThread.fromSnapshot(
    AgentChatSnapshot.fromJson(<String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'cursor': 1,
      'session': <String, Object?>{
        'status': running ? 'running' : 'idle',
        if (running) 'activeTurnId': 'turn-1',
      },
      'turns': <Object?>[
        if (turnStatus != null)
          <String, Object?>{'turnId': 'turn-1', 'status': turnStatus},
      ],
      'items': <Object?>[
        <String, Object?>{
          'itemId': 'u1',
          'turnId': 'turn-1',
          'type': 'user_message',
          'status': 'completed',
          'createdAt': '2026-10-12T10:00:00Z',
          'updatedAt': '2026-10-12T10:00:00Z',
          'text': 'Go',
        },
      ],
      'pendingRequests': requests,
    }),
  ),
);

const Map<String, Object?> _approval = <String, Object?>{
  'requestId': 'r1',
  'kind': 'commandExecutionApproval',
  'createdAt': '2026-10-12T10:00:00Z',
};

void main() {
  group('AgentChatTimelineAnnouncer', () {
    test('announces a new request once', () {
      final before = _projection(running: true);
      final after = _projection(
        running: true,
        requests: <Map<String, Object?>>[_approval],
      );
      expect(
        AgentChatTimelineAnnouncer.transitions(before: before, after: after),
        <String>['Run Command? The agent is waiting for your decision.'],
      );
      expect(
        AgentChatTimelineAnnouncer.transitions(before: after, after: after),
        isEmpty,
      );
    });

    test('announces how a running turn settled', () {
      final running = _projection(running: true);
      expect(
        AgentChatTimelineAnnouncer.transitions(
          before: running,
          after: _projection(turnStatus: 'completed'),
        ),
        <String>['The agent finished.'],
      );
      expect(
        AgentChatTimelineAnnouncer.transitions(
          before: running,
          after: _projection(turnStatus: 'failed'),
        ),
        <String>['The turn failed.'],
      );
      // A turn that was already settled says nothing again.
      final settled = _projection(turnStatus: 'failed');
      expect(
        AgentChatTimelineAnnouncer.transitions(before: settled, after: settled),
        isEmpty,
      );
    });
  });

  group('AgentChatTimelineSessions', () {
    test('keeps one session per chat and drops the least recent', () {
      final sessions = AgentChatTimelineSessions();
      final first = sessions.of('chat-0');
      for (
        var index = 1;
        index <= AgentChatTimelineSessions.limit;
        index += 1
      ) {
        sessions.of('chat-$index');
      }
      expect(sessions.length, AgentChatTimelineSessions.limit);
      expect(identical(sessions.of('chat-0'), first), isFalse);
      final kept = sessions.of('chat-5');
      expect(identical(sessions.of('chat-5'), kept), isTrue);
    });

    test('a fresh session follows and has nothing open', () {
      final session = AgentChatTimelineSessions().of('chat');
      expect(session.mode, AgentChatScrollMode.following);
      expect(session.expansion.isExpanded('turn-1', byDefault: false), isFalse);
      expect(session.seenRequestIds, isEmpty);
    });
  });
}
