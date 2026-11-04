import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('a question wake keeps its request ids and asks, not finishes', () {
    final projection = AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'session': <String, Object?>{'status': 'running'},
          'items': <Object?>[
            <String, Object?>{
              'itemId': 'q1',
              'turnId': 'turn-1',
              'type': 'user_message',
              'status': 'completed',
              'createdAt': '2026-10-12T10:00:00Z',
              'updatedAt': '2026-10-12T10:00:00Z',
              'text': 'Delegated task t1 asked',
              'normalized': <String, Object?>{
                'origin': <String, Object?>{
                  'kind': 'orchestrationWake',
                  'taskIds': <Object?>['t1'],
                  'requestIds': <Object?>['r1'],
                },
              },
            },
          ],
        }),
      ),
    );
    final section = projection.entries
        .whereType<AgentChatTurnEntry>()
        .first
        .section;
    final origin = section.prompts.single.origin!;
    expect(origin.requestIds, <String>['r1']);
    expect(origin.asksQuestion, isTrue);
    expect(agentChatOriginHeading(origin), 'A delegated task asked a question');
  });
}
