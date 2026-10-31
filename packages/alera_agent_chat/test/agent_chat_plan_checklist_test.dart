import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String turnId = 'turn-1',
  String text = '',
  Map<String, Object?> normalized = const <String, Object?>{},
  Map<String, Object?> data = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': turnId,
  'type': type,
  'status': 'completed',
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'text': text,
  'normalized': normalized,
  'data': data,
};

Map<String, Object?> _plan(
  List<Map<String, Object?>> steps, {
  String turnId = 'turn-1',
}) => _item(
  'plan:$turnId',
  'plan',
  turnId: turnId,
  normalized: <String, Object?>{'planSteps': steps},
);

AgentChatTimelineProjection _projection(List<Map<String, Object?>> items) =>
    AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'session': <String, Object?>{'status': 'idle'},
          'items': items,
        }),
      ),
    );

AgentChatTurnSection _section(AgentChatTimelineProjection projection) =>
    projection.entries.whereType<AgentChatTurnEntry>().last.section;

void main() {
  final prompt = _item('u1', 'user_message', text: 'Go');
  final steps = <Map<String, Object?>>[
    <String, Object?>{'step': 'Inspect', 'status': 'inProgress'},
  ];

  test('an emptied checklist is neither docked nor a row', () {
    final projection = _projection(<Map<String, Object?>>[
      prompt,
      _plan(const <Map<String, Object?>>[]),
    ]);
    final section = _section(projection);
    expect(section.planSteps, isNull);
    expect(section.answers, isEmpty);
    expect(section.activity, isEmpty);
    expect(projection.activePlanSteps, isNull);
  });

  test('a checklist with tasks docks again', () {
    final projection = _projection(<Map<String, Object?>>[
      prompt,
      _plan(steps),
    ]);
    expect(projection.activePlanSteps?.planSteps.single.step, 'Inspect');
  });

  test('an emptied checklist clears an earlier one of its turn', () {
    final projection = _projection(<Map<String, Object?>>[
      prompt,
      <String, Object?>{..._plan(steps), 'itemId': 'plan-a'},
      _plan(const <Map<String, Object?>>[]),
    ]);
    expect(_section(projection).planSteps, isNull);
    expect(projection.activePlanSteps, isNull);
  });

  test('a proposed plan is still an answer', () {
    final section = _section(
      _projection(<Map<String, Object?>>[
        prompt,
        _item(
          'p1',
          'plan',
          text: 'Do the thing.',
          data: <String, Object?>{'text': 'Do the thing.'},
        ),
      ]),
    );
    expect(section.planSteps, isNull);
    expect(section.answers.single.id, 'p1');
  });
}
