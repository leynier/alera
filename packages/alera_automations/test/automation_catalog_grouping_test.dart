import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

AutomationRecord _automation(
  String id,
  String name, {
  String state = 'active',
  String? projectId,
  bool attention = false,
}) => AutomationRecord.fromJson(<String, Object?>{
  'id': id,
  'name': name,
  'state': state,
  'projectId': ?projectId,
  if (attention)
    'attention': <String, Object?>{'code': 'x', 'message': 'Look at this'},
});

void main() {
  test('each project appears once, ordered by name, with Others last', () {
    final groups = groupAutomations(
      <AutomationRecord>[
        _automation('1', 'b', projectId: 'p2'),
        _automation('2', 'a'),
        _automation('3', 'c', projectId: 'p1'),
        _automation('4', 'd', projectId: 'p2'),
      ],
      keyOf: (automation) => automation.projectId,
      labelOf: (key) => switch (key) {
        'p1' => 'zeta',
        _ => 'Alpha',
      },
    );
    expect(groups.map((group) => group.label), <String>[
      'Alpha',
      'zeta',
      'Others',
    ]);
    expect(groups.first.key, 'p2');
    expect(groups.first.automations.map((item) => item.id), <String>['1', '4']);
    expect(groups.last.key, isNull);
  });

  test('inside a group attention comes first, then state, then name', () {
    final groups = groupAutomations(
      <AutomationRecord>[
        _automation('trash', 'A', state: 'trashed'),
        _automation('draft', 'A', state: 'draft'),
        _automation('paused', 'A', state: 'paused'),
        _automation('active-b', 'b'),
        _automation('active-a', 'A'),
        _automation('blocked', 'Z', state: 'blocked'),
        _automation('done', 'A', state: 'archived'),
        _automation('attention', 'Z', state: 'paused', attention: true),
      ],
      keyOf: (_) => 'all',
      labelOf: (key) => key,
    );
    expect(groups.single.automations.map((item) => item.id), <String>[
      'blocked',
      'attention',
      'active-a',
      'active-b',
      'paused',
      'draft',
      'done',
      'trash',
    ]);
  });

  test('no automations means no groups', () {
    expect(
      groupAutomations(
        const <AutomationRecord>[],
        keyOf: (automation) => automation.projectId,
        labelOf: (key) => key,
      ),
      isEmpty,
    );
  });
}
