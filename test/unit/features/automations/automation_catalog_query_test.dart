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
  test('associations name where they came from', () {
    AutomationAssociationSource? source(String value) =>
        AutomationAssociation.tryParse(<String, Object?>{'source': value})
            ?.source;
    expect(source('origin'), AutomationAssociationSource.origin);
    expect(
      source('targetWorkspace'),
      AutomationAssociationSource.targetWorkspace,
    );
    expect(source('project'), AutomationAssociationSource.project);
    expect(AutomationAssociation.tryParse('ws-1'), isNull);
  });

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

  test('named filters narrow by project, host, profile, tag and text', () {
    final automation = AutomationRecord.fromJson(<String, Object?>{
      'id': 'nightly',
      'name': 'Nightly',
      'slug': 'nightly-review',
      'description': 'Checks flaky builds',
      'promptTemplate': 'Summarize open pull requests',
      'state': 'active',
      'projectId': 'p-1',
      'targetHostId': 'ssh-1',
      'tagIds': <Object?>['ops'],
      'target': <String, Object?>{
        'freshTab': <String, Object?>{'agentProfileId': 'codex'},
      },
    });
    const none = AutomationCatalogFilters();
    expect(none.isFiltered, isFalse);
    expect(none.matches(automation), isTrue);
    for (final (filters, expected) in <(AutomationCatalogFilters, bool)>[
      (const AutomationCatalogFilters(projectId: 'p-1'), true),
      (const AutomationCatalogFilters(projectId: 'p-2'), false),
      (const AutomationCatalogFilters(hostId: 'ssh-1'), true),
      (const AutomationCatalogFilters(hostId: 'local'), false),
      (const AutomationCatalogFilters(profileId: 'codex'), true),
      (const AutomationCatalogFilters(profileId: 'claude'), false),
      (const AutomationCatalogFilters(tagId: 'ops'), true),
      (const AutomationCatalogFilters(tagId: 'docs'), false),
      (const AutomationCatalogFilters(search: 'REVIEW'), true),
      (const AutomationCatalogFilters(search: 'flaky'), true),
      (const AutomationCatalogFilters(search: 'pull requests'), true),
      (const AutomationCatalogFilters(search: 'deploy'), false),
    ]) {
      expect(filters.isFiltered, isTrue);
      expect(filters.matches(automation), expected, reason: '$filters');
    }
  });
}
