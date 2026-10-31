import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatItem _image(String id, {String status = 'completed', String? path}) =>
    AgentChatItem.fromJson(<String, Object?>{
      'itemId': id,
      'turnId': 'turn-1',
      'type': 'image_generation',
      'status': status,
      'createdAt': '2026-10-12T10:00:00Z',
      'title': 'Generated image',
      'normalized': <String, Object?>{'imagePath': ?path},
      'data': <String, Object?>{'savedPath': ?path},
    });

void main() {
  test('generated images are work the agent did', () {
    expect(
      AgentChatItemType.fromJson('image_generation'),
      AgentChatItemType.imageGeneration,
    );
    expect(AgentChatItemType.imageGeneration.isActivity, isTrue);
    final item = _image('i1', path: '/tmp/out/first.png');
    expect(item.type, AgentChatItemType.imageGeneration);
    expect(item.imagePath, '/tmp/out/first.png');
  });

  test('an image action names the file it saved', () {
    final done = AgentChatWorkedAction.fromItem(
      _image('i1', path: '/tmp/out/first.png'),
    );
    expect(done.kind, AgentChatWorkedActionKind.generateImage);
    expect(done.label, 'Generated first.png');
    final running = AgentChatWorkedAction.fromItem(
      _image('i2', status: 'inProgress'),
    );
    expect(running.label, 'Generated an image');
    expect(agentChatWorkedActionLiveLabel(running), 'Generating an image');
    expect(
      agentChatWorkedSummary(<AgentChatWorkedAction>[done, running]),
      'Generated 2 images',
    );
  });

  test('a running turn shows the image it generates', () {
    final thread = AgentChatThread.fromSnapshot(
      AgentChatSnapshot.fromJson(<String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'ws-1',
        'cursor': 1,
        'session': <String, Object?>{
          'status': 'running',
          'activeTurnId': 'turn-1',
        },
        'items': <Object?>[
          <String, Object?>{
            'itemId': 'i1',
            'turnId': 'turn-1',
            'type': 'image_generation',
            'status': 'inProgress',
            'createdAt': '2026-10-12T10:00:00Z',
          },
        ],
      }),
    );
    final section = AgentChatTimelineProjection.build(thread).entries
        .whereType<AgentChatTurnEntry>()
        .single
        .section;
    expect(section.activity.single, isA<AgentChatActionGroupRow>());
    expect(section.liveWork!.label, 'Generating an image');
  });
}
