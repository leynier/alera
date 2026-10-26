import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String? turnId = 'turn-1',
  String text = '',
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': 'completed',
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'text': text,
  'normalized': normalized,
};

Map<String, Object?> _command(String id, String command) => _item(
  id,
  'command_execution',
  normalized: <String, Object?>{'command': command},
);

AgentChatTimelineProjection _projection(
  List<Map<String, Object?>> items, {
  List<AgentChatOutgoingMessage> outgoing = const <AgentChatOutgoingMessage>[],
}) => AgentChatTimelineProjection.build(
  AgentChatThread.fromSnapshot(
    AgentChatSnapshot.fromJson(<String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'cursor': 1,
      'session': <String, Object?>{'status': 'idle'},
      'turns': <Object?>[
        <String, Object?>{
          'turnId': 'turn-1',
          'status': 'completed',
          'startedAt': '2026-10-12T10:00:00Z',
          'completedAt': '2026-10-12T10:00:03Z',
        },
      ],
      'items': items,
      'pendingRequests': <Object?>[],
    }),
  ),
  outgoing: outgoing,
);

void main() {
  test('finds rows in timeline order, ignoring case', () {
    final projection = _projection(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Fix the Sidebar'),
      _command('c1', 'rg sidebar lib'),
      _command('c2', 'flutter test'),
      _item('a1', 'assistant_message', text: 'The sidebar is fixed.'),
    ]);

    final matches = agentChatFindMatches(projection, '  SIDEBAR ');

    expect(matches.map((match) => match.targetKey), <String>[
      agentChatFindMessageTargetKey('u1'),
      'activity-actions-c1',
      agentChatFindAnswerTargetKey('a1'),
    ]);
    expect(matches.map((match) => match.entryKey).toSet(), <String>{
      'turn-turn-1',
    });
  });

  test('a match in folded work opens the turn and its group', () {
    final projection = _projection(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Go'),
      _command('c1', 'ls'),
      _command('c2', 'cat pubspec.yaml'),
      _item('a1', 'assistant_message', text: 'Done.'),
    ]);

    final match = agentChatFindMatches(projection, 'pubspec').single;

    expect(match.foldKeys, <String>[
      agentChatTurnFoldKey('turn-1'),
      'actions-c1',
    ]);
  });

  test('a plan opens its full text', () {
    final projection = _projection(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Plan it'),
      _item('p1', 'plan', text: '# Plan\n\n1. Rename the parser'),
    ]);

    final match = agentChatFindMatches(projection, 'parser').single;

    expect(match.targetKey, agentChatFindAnswerTargetKey('p1'));
    expect(match.foldKeys, <String>[agentChatPlanFoldKey('p1')]);
  });

  test('finds standalone notices and unsent messages', () {
    final projection = _projection(
      <Map<String, Object?>>[
        _item('n1', 'notice', turnId: null, text: 'Model changed to opus'),
      ],
      outgoing: <AgentChatOutgoingMessage>[
        AgentChatOutgoingMessage(
          clientMessageId: 'm1',
          text: 'Use opus please',
          createdAt: DateTime.utc(2026, 10, 12),
        ),
      ],
    );

    final matches = agentChatFindMatches(projection, 'opus');

    expect(matches.map((match) => match.targetKey), <String>[
      agentChatFindItemTargetKey('n1'),
      agentChatFindOutgoingTargetKey('m1'),
    ]);
  });

  test('an empty query and reasoning never match', () {
    final projection = _projection(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Go'),
      _item('r1', 'reasoning', text: 'thinking about secrets'),
    ]);

    expect(agentChatFindMatches(projection, '   '), isEmpty);
    expect(agentChatFindMatches(projection, 'secrets'), isEmpty);
  });
}
