import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

AutomationRecord _record(
  String id, {
  String state = 'active',
  Map<String, Object?>? association,
  Map<String, Object?>? attention,
  String? projectId,
}) => AutomationRecord.fromJson(<String, Object?>{
  'id': id,
  'name': id,
  'state': state,
  'projectId': ?projectId,
  'association': ?association,
  'attention': ?attention,
  'target': <String, Object?>{
    'freshTab': <String, Object?>{'workspaceId': 'target-ws'},
  },
});

void main() {
  final records = <AutomationRecord>[
    _record(
      'active',
      association: {
        'workspaceId': 'ws-1',
        'sectionId': 's-1',
        'projectId': 'p-1',
        'source': 'origin',
      },
    ),
    _record('blocked', state: 'blocked', projectId: 'p-2'),
    _record('flagged', attention: {'code': 'x', 'message': 'Needs a target'}),
    _record('done', state: 'archived'),
    _record('gone', state: 'trashed'),
    _record('draft', state: 'draft'),
  ];

  test('All hides trash but keeps completed definitions visible', () {
    final visible = visibleAutomations(
      records,
      AutomationScope.all,
      const AutomationCatalogFilters(),
    ).map((item) => item.id);
    expect(visible, containsAll(<String>['done', 'draft', 'active']));
    expect(visible, isNot(contains('gone')));
    expect(visible.take(2), unorderedEquals(<String>['blocked', 'flagged']));
  });

  test('buckets count completed, trash and attention', () {
    final counts = automationBucketCounts(records, AutomationScope.all);
    expect(counts[AutomationBucket.completed], 1);
    expect(counts[AutomationBucket.trash], 1);
    expect(counts[AutomationBucket.needsAttention], 2);
    expect(counts[AutomationBucket.active], 2);
    expect(counts[AutomationBucket.drafts], 1);
  });

  test('scopes follow the runtime association, origin before target', () {
    const workspace = AutomationScope(kind: .workspace, id: 'ws-1');
    const section = AutomationScope(kind: .section, id: 's-1');
    const project = AutomationScope(kind: .project, id: 'p-2');
    const targetWorkspace = AutomationScope(kind: .workspace, id: 'target-ws');
    List<String> ids(AutomationScope scope) => visibleAutomations(
      records,
      scope,
      const AutomationCatalogFilters(),
    ).map((item) => item.id).toList();
    expect(ids(workspace), <String>['active']);
    expect(ids(section), <String>['active']);
    expect(ids(project), <String>['blocked']);
    expect(ids(targetWorkspace), isNot(contains('active')));
  });

  test('a bucket filter shows trash only when asked for', () {
    final trash = visibleAutomations(
      records,
      AutomationScope.all,
      const AutomationCatalogFilters(bucket: AutomationBucket.trash),
    );
    expect(trash.single.id, 'gone');
  });
}
