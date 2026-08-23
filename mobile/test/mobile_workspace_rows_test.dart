import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity sort ranks terminals first and inactive names last', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('inactive-zebra', now, name: 'zebra'),
        _workspace(
          'idle-terminal',
          now.subtract(const Duration(minutes: 1)),
          name: 'idle',
        ),
        _workspace(
          'working',
          now.subtract(const Duration(minutes: 4)),
          name: 'working',
        ),
        _workspace(
          'done',
          now.subtract(const Duration(minutes: 3)),
          name: 'done',
        ),
        _workspace(
          'waiting',
          now.subtract(const Duration(minutes: 2)),
          name: 'waiting',
        ),
        _workspace(
          'inactive-alpha',
          now.subtract(const Duration(days: 1)),
          name: 'alpha',
        ),
      ],
      projects: const [],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        workspaceSort: MobileWorkbenchSortBy.activity,
      ),
      activity: <String, DateTime>{
        'inactive-zebra': now,
        'idle-terminal': now.subtract(const Duration(minutes: 1)),
        'working': now.subtract(const Duration(minutes: 4)),
        'done': now.subtract(const Duration(minutes: 3)),
        'waiting': now.subtract(const Duration(minutes: 2)),
      },
      agentPresence: <AgentPresenceSummary>[
        _presence(
          'working',
          'working',
          now.subtract(const Duration(minutes: 4)),
        ),
        _presence('done', 'done', now.subtract(const Duration(minutes: 3))),
        _presence(
          'waiting',
          'waiting',
          now.subtract(const Duration(minutes: 2)),
        ),
      ],
      terminalTabCountByWorkspaceId: const <String, int>{'idle-terminal': 1},
      now: now,
    );

    expect(_workspaceIds(rows), <String>[
      'waiting',
      'done',
      'working',
      'idle-terminal',
      'inactive-alpha',
      'inactive-zebra',
    ]);
  });

  test('Stale presence keeps its terminal ahead of inactive workspaces', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('recent', now),
        _workspace('stale', now.subtract(const Duration(hours: 1))),
      ],
      projects: const [],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        workspaceSort: MobileWorkbenchSortBy.activity,
      ),
      activity: <String, DateTime>{'recent': now},
      agentPresence: <AgentPresenceSummary>[
        _presence('stale', 'blocked', now.subtract(const Duration(hours: 1))),
      ],
      now: now,
    );

    expect(_workspaceIds(rows), <String>['stale', 'recent']);
  });

  test('An open terminal is active without live agent presence', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('inactive', now, name: 'alpha'),
        _workspace(
          'terminal',
          now.subtract(const Duration(days: 1)),
          name: 'zebra',
        ),
      ],
      projects: const [],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        workspaceSort: MobileWorkbenchSortBy.activity,
      ),
      terminalTabCountByWorkspaceId: const <String, int>{'terminal': 1},
      now: now,
    );

    expect(_workspaceIds(rows), <String>['terminal', 'inactive']);
  });

  test('Active filter keeps terminal and agent workspaces only', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('inactive', now),
        _workspace('terminal', now),
        _workspace('codex', now),
      ],
      projects: const [],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        showActiveWorkspacesOnly: true,
      ),
      terminalTabCountByWorkspaceId: const <String, int>{'terminal': 1},
      agentPresence: <AgentPresenceSummary>[_presence('codex', 'working', now)],
      now: now,
    );

    expect(_workspaceIds(rows), <String>['codex', 'terminal']);
  });

  test('Composes project, tag, kind, and normalized search filters', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('kept', now, projectId: 'p1', tagIds: const ['selected']),
        _workspace(
          'wrong-project',
          now,
          projectId: 'p2',
          tagIds: const ['selected'],
        ),
        _workspace('wrong-tag', now, projectId: 'p1'),
        _workspace(
          'wrong-kind',
          now,
          projectId: 'p1',
          kind: 'main',
          tagIds: const ['selected'],
        ),
      ],
      projects: <ProjectSummary>[
        _project('p1', 'Project Alpha', now),
        _project('p2', 'Project Beta', now),
      ],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        selectedProjectIds: <String>{'p1'},
        selectedTagIds: <String>{'selected'},
        workspaceKindFilter: MobileWorkspaceKindFilter.nonDefaultOnly,
      ),
      searchQuery: '  PROJECT ALPHA  ',
      now: now,
    );

    expect(_workspaceIds(rows), <String>['kept']);
  });

  test('Inactive projects sort alphabetically after active projects', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('active', now, projectId: 'p-zeta'),
        _workspace('inactive-zeta', now, projectId: 'p-charlie'),
        _workspace('inactive-alpha', now, projectId: 'p-alpha'),
      ],
      projects: <ProjectSummary>[
        _project('p-charlie', 'Charlie', now),
        _project('p-zeta', 'Zeta', now.subtract(const Duration(days: 1))),
        _project('p-alpha', 'Alpha', now.subtract(const Duration(days: 2))),
      ],
      prefs: const MobileViewPrefs(projectSort: MobileWorkbenchSortBy.activity),
      terminalTabCountByWorkspaceId: const <String, int>{'active': 1},
      now: now,
    );

    expect(
      rows
          .whereType<MobileProjectHeaderRow>()
          .map((row) => row.projectId)
          .toList(),
      <String>['p-zeta', 'p-alpha', 'p-charlie'],
    );
  });

  test('An active descendant promotes its workspace tree', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('inactive-root', now, name: 'alpha-root'),
        _workspace('active-root', now, name: 'zeta-root'),
        _workspace(
          'active-child',
          now,
          name: 'active-child',
          parentWorkspaceId: 'active-root',
        ),
      ],
      projects: const [],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        workspaceSort: MobileWorkbenchSortBy.activity,
      ),
      terminalTabCountByWorkspaceId: const <String, int>{'active-child': 1},
      now: now,
    );

    expect(_workspaceIds(rows), <String>[
      'active-root',
      'active-child',
      'inactive-root',
    ]);
  });
}

WorkspaceSummary _workspace(
  String id,
  DateTime updatedAt, {
  String? name,
  String projectId = 'project',
  String? parentWorkspaceId,
  String kind = 'linked',
  List<String> tagIds = const <String>[],
}) {
  return WorkspaceSummary(
    id: id,
    projectId: projectId,
    name: name ?? id,
    path: '/tmp/$id',
    parentWorkspaceId: parentWorkspaceId,
    kind: kind,
    tagIds: tagIds,
    updatedAt: updatedAt,
  );
}

ProjectSummary _project(String id, String name, DateTime updatedAt) {
  return ProjectSummary(
    id: id,
    name: name,
    repoPath: '/tmp/$id',
    updatedAt: updatedAt,
  );
}

AgentPresenceSummary _presence(String workspaceId, String state, DateTime at) {
  return AgentPresenceSummary(
    terminalSessionId: 'session-$workspaceId',
    workspaceId: workspaceId,
    tabId: 'tab-$workspaceId',
    agentType: 'codex',
    state: state,
    stateStartedAt: at,
  );
}

List<String> _workspaceIds(List<MobileWorkspaceRow> rows) {
  return <String>[
    for (final row in rows)
      if (row is MobileWorkspaceEntryRow) row.entry.workspace.id,
  ];
}
