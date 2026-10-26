import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatSummary _chat(
  String id, {
  String? parent,
  String? forkedFrom,
  bool busy = false,
  bool archived = false,
  String status = 'ready',
  int minute = 0,
}) => AgentChatSummary.fromJson(<String, Object?>{
  'chatId': id,
  'workspaceId': 'w',
  'title': 'Chat $id',
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'status': status,
  'busy': busy,
  'archived': archived,
  'updatedAt': DateTime.utc(2026, 10, 12, 10, minute).toIso8601String(),
  'parentChatId': ?parent,
  'forkedFromChatId': ?forkedFrom,
});

AgentChatItem _call(String id, String status, {int minute = 0}) =>
    AgentChatItem.fromJson(<String, Object?>{
      'itemId': id,
      'turnId': 't',
      'type': 'collab_agent_tool_call',
      'status': 'completed',
      'createdAt': DateTime.utc(2026, 10, 12, 9, minute).toIso8601String(),
      'normalized': <String, Object?>{
        'subagent': <String, Object?>{
          'status': status,
          'description': 'Agent $id',
        },
      },
    });

void main() {
  test('parents pin first, then forks; agents split by whether they run', () {
    final relationships = AgentChatRelationships.build(
      chatId: 'me',
      chats: <AgentChatSummary>[
        _chat('me', parent: 'boss', forkedFrom: 'origin'),
        _chat('boss'),
        _chat('origin'),
        _chat('fork-old', forkedFrom: 'me', minute: 1),
        _chat('fork-new', forkedFrom: 'me', minute: 5),
        _chat('fork-gone', forkedFrom: 'me', archived: true),
        _chat('helper', parent: 'me', busy: true),
        _chat('done-helper', parent: 'me', status: 'error'),
        _chat('stranger'),
      ],
      items: <AgentChatItem>[
        _call('live', 'running'),
        _call('finished', 'completed', minute: 3),
        _call('broke', 'failed', minute: 4),
      ],
    );
    expect(relationships.related.map((relation) => relation.chatId), <String?>[
      'boss',
      'origin',
      'fork-new',
      'fork-old',
    ]);
    expect(relationships.related.first.kind, AgentChatRelationKind.parentChat);
    expect(relationships.mergeTarget?.chatId, 'origin');
    expect(
      relationships.active.map((relation) => relation.title),
      unorderedEquals(<String>['Chat helper', 'Agent live']),
    );
    expect(relationships.runningCount, 2);
    expect(relationships.heading, 'Lineage · 2 running');
    // Newest first: the delegated chat changed after the agents started.
    expect(relationships.previous.map((relation) => relation.title), <String>[
      'Chat done-helper',
      'Agent broke',
      'Agent finished',
    ]);
    expect(relationships.failedPreviousCount, 2);
  });

  test('a missing parent stays listed but cannot open', () {
    final relationships = AgentChatRelationships.build(
      chatId: 'me',
      chats: <AgentChatSummary>[_chat('me', parent: 'gone')],
    );
    final parent = relationships.related.single;
    expect(parent.missing, isTrue);
    expect(parent.statusLabel, 'Unavailable');
    expect(relationships.mergeTarget, isNull);
  });

  test('a chat with no lineage has no relationships', () {
    expect(
      AgentChatRelationships.build(
        chatId: 'me',
        chats: <AgentChatSummary>[_chat('me')],
      ).isEmpty,
      isTrue,
    );
  });
}
