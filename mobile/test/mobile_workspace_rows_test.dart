import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity sort matches desktop urgency before shared recency', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final rows = buildMobileWorkspaceRows(
      workspaces: <WorkspaceSummary>[
        _workspace('idle', now.subtract(const Duration(minutes: 1))),
        _workspace('working', now.subtract(const Duration(minutes: 4))),
        _workspace('done', now.subtract(const Duration(minutes: 3))),
        _workspace('waiting', now.subtract(const Duration(minutes: 2))),
      ],
      projects: const [],
      prefs: const MobileViewPrefs(
        groupBy: MobileWorkspaceGroupBy.none,
        workspaceSort: MobileWorkbenchSortBy.activity,
      ),
      activity: <String, DateTime>{
        'idle': now,
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
      now: now,
    );

    expect(_workspaceIds(rows), <String>['waiting', 'done', 'working', 'idle']);
  });

  test('Stale presence falls back to shared activity', () {
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

    expect(_workspaceIds(rows), <String>['recent', 'stale']);
  });
}

WorkspaceSummary _workspace(String id, DateTime updatedAt) {
  return WorkspaceSummary(
    id: id,
    projectId: 'project',
    name: id,
    path: '/tmp/$id',
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
