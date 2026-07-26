import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/resource_manager/application/resource_snapshot_projection.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 7, 25);

Project _project(String id, String name) => Project(
  id: id,
  name: name,
  repoPath: '/repos/$id',
  createdAt: _now,
  updatedAt: _now,
);

Workspace _workspace(
  String id,
  String name, {
  String projectId = 'p1',
  String hostId = 'local',
}) => Workspace(
  id: id,
  projectId: projectId,
  name: name,
  path: '/repos/$projectId/$id',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
  hostId: hostId,
);

WorkspaceTabRecord _tab(
  String id,
  String workspaceId, {
  required String sessionId,
  String title = 'Terminal',
  WorkspaceTabKind kind = WorkspaceTabKind.terminal,
}) => WorkspaceTabRecord(
  id: id,
  workspaceId: workspaceId,
  title: title,
  createdAt: _now,
  updatedAt: _now,
  kind: kind,
  payload: <String, Object?>{
    workspaceTabTerminalSessionIdPayloadKey: sessionId,
  },
);

ResourceSessionSample _session(
  String sessionId, {
  required String workspaceId,
  required String tabId,
  double cpuPercent = 0,
  int memoryBytes = 0,
  bool measured = true,
  bool running = true,
}) => ResourceSessionSample(
  sessionId: sessionId,
  workspaceId: workspaceId,
  tabId: tabId,
  running: running,
  shellPid: running ? 4242 : null,
  measured: measured,
  cpuPercent: cpuPercent,
  memoryBytes: memoryBytes,
  processCount: 1,
  history: const <int>[1, 2],
);

/// One core by default, so the grouping and ordering cases below read the
/// host's per-core percentages back unchanged. The unit conversion itself is
/// covered separately, with a core count that actually divides.
ResourceSnapshot _snapshot(
  List<ResourceSessionSample> sessions, {
  int cpuCoreCount = 1,
}) => ResourceSnapshot(
  collectedAt: _now,
  warming: false,
  host: ResourceHostMetrics(
    totalMemoryBytes: 16 * 1024 * 1024 * 1024,
    availableMemoryBytes: 8 * 1024 * 1024 * 1024,
    usedMemoryBytes: 8 * 1024 * 1024 * 1024,
    memoryUsagePercent: 50,
    cpuCoreCount: cpuCoreCount,
    loadAverage1m: 1,
  ),
  hostProcess: null,
  appProcess: null,
  sessions: sessions,
  totalCpuPercent: 0,
  totalMemoryBytes: 0,
);

void main() {
  group('buildResourceTree', () {
    test('groups sessions under their workspace and project', () {
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session(
            's1',
            workspaceId: 'w1',
            tabId: 't1',
            cpuPercent: 10,
            memoryBytes: 100,
          ),
          _session(
            's2',
            workspaceId: 'w1',
            tabId: 't2',
            cpuPercent: 5,
            memoryBytes: 50,
          ),
        ]),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[
          _tab('t1', 'w1', sessionId: 's1', title: 'Agent'),
          _tab('t2', 'w1', sessionId: 's2', title: 'Build'),
        ],
      );

      final project = tree.projects.single;
      expect(project.name, 'Alera');
      expect(project.cpuMachinePercent, 15);
      expect(project.memoryBytes, 150);

      final workspace = project.workspaces.single;
      expect(workspace.name, 'Main');
      expect(workspace.remote, isFalse);
      expect(workspace.cpuMachinePercent, 15);
      expect(workspace.memoryBytes, 150);
      expect(workspace.sessions.map((session) => session.label), <String>[
        'Agent',
        'Build',
      ]);
      expect(tree.orphanSessions, isEmpty);
    });

    test('cpu is projected as a share of the machine, not of one core', () {
      // The host measures what `sysinfo` measures: percent of a single core, so
      // a session spread over three of eight cores arrives as 320%.
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session('s1', workspaceId: 'w1', tabId: 't1', cpuPercent: 320),
          _session('s2', workspaceId: 'w1', tabId: 't2', cpuPercent: 8),
        ], cpuCoreCount: 8),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[
          _tab('t1', 'w1', sessionId: 's1', title: 'Agent'),
          _tab('t2', 'w1', sessionId: 's2', title: 'Build'),
        ],
      );

      final workspace = tree.projects.single.workspaces.single;
      expect(
        workspace.sessions.map((session) => session.cpuMachinePercent),
        <double>[40, 1],
      );
      expect(workspace.cpuMachinePercent, 41);
      expect(tree.projects.single.cpuMachinePercent, 41);
    });

    test('an unknown core count leaves cpu absent rather than raw', () {
      // What an unavailable snapshot carries. Passing the per-core number
      // through would label it as a machine share and read 8x too high here.
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session(
            's1',
            workspaceId: 'w1',
            tabId: 't1',
            cpuPercent: 320,
            memoryBytes: 100,
          ),
        ], cpuCoreCount: 0),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[_tab('t1', 'w1', sessionId: 's1')],
      );

      final session = tree.projects.single.workspaces.single.sessions.single;
      expect(session.cpuMachinePercent, isNull);
      // Memory does not depend on the core count and still reads.
      expect(session.memoryBytes, 100);
    });

    test('a session with no tab becomes an orphan outside the tree', () {
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session('kept', workspaceId: 'w1', tabId: 't1', memoryBytes: 10),
          _session('lost', workspaceId: 'w1', tabId: 'gone', memoryBytes: 20),
        ]),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[_tab('t1', 'w1', sessionId: 'kept')],
      );

      expect(
        tree.projects.single.workspaces.single.sessions.map(
          (session) => session.sessionId,
        ),
        <String>['kept'],
      );
      final orphan = tree.orphanSessions.single;
      expect(orphan.sessionId, 'lost');
      expect(orphan.orphan, isTrue);
      // Falls back to the session id because there is no tab to name it.
      expect(orphan.label, 'lost');
      // The workspace aggregate must exclude the orphan.
      expect(tree.projects.single.workspaces.single.memoryBytes, 10);
    });

    test('a non-terminal tab never claims a session', () {
      // Only terminal tabs own PTYs; an editor tab sharing an id must not stop
      // a session from being reported as orphaned.
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session('s1', workspaceId: 'w1', tabId: 't1'),
        ]),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[
          _tab('s1', 'w1', sessionId: 's1', kind: WorkspaceTabKind.editor),
        ],
      );

      expect(tree.projects, isEmpty);
      expect(tree.orphanSessions.single.sessionId, 's1');
    });

    test('a remote workspace reports absent metrics rather than zero', () {
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session(
            's1',
            workspaceId: 'w1',
            tabId: 't1',
            cpuPercent: 9,
            memoryBytes: 90,
          ),
        ]),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Remote', hostId: 'ssh-box')],
        tabs: <WorkspaceTabRecord>[_tab('t1', 'w1', sessionId: 's1')],
      );

      final workspace = tree.projects.single.workspaces.single;
      expect(workspace.remote, isTrue);
      expect(workspace.sessions.single.cpuMachinePercent, isNull);
      expect(workspace.sessions.single.memoryBytes, isNull);
      expect(workspace.cpuMachinePercent, isNull);
      expect(workspace.memoryBytes, isNull);
      expect(tree.projects.single.memoryBytes, isNull);
    });

    test('an unmeasured local session reports absent metrics', () {
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session(
            's1',
            workspaceId: 'w1',
            tabId: 't1',
            measured: false,
            running: false,
          ),
        ]),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[_tab('t1', 'w1', sessionId: 's1')],
      );

      expect(
        tree.projects.single.workspaces.single.sessions.single.memoryBytes,
        isNull,
      );
    });

    test('sessions for an unknown workspace are dropped', () {
      // Only happens mid-sync; inventing a group would be worse than waiting.
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session('s1', workspaceId: 'ghost', tabId: 't1'),
        ]),
        projects: <Project>[_project('p1', 'Alera')],
        workspaces: const <Workspace>[],
        tabs: <WorkspaceTabRecord>[_tab('t1', 'ghost', sessionId: 's1')],
      );

      expect(tree.projects, isEmpty);
      expect(tree.orphanSessions, isEmpty);
      expect(tree.isEmpty, isTrue);
    });

    test('a project without a record falls back to its id', () {
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session('s1', workspaceId: 'w1', tabId: 't1'),
        ]),
        projects: const <Project>[],
        workspaces: <Workspace>[_workspace('w1', 'Main')],
        tabs: <WorkspaceTabRecord>[_tab('t1', 'w1', sessionId: 's1')],
      );

      expect(tree.projects.single.name, 'p1');
    });
  });

  group('sorting', () {
    ResourceTree buildWithSort(
      ResourceSortColumn column, {
      int cpuCoreCount = 1,
    }) => buildResourceTree(
      snapshot: _snapshot(<ResourceSessionSample>[
        _session(
          'low',
          workspaceId: 'w1',
          tabId: 't1',
          cpuPercent: 1,
          memoryBytes: 10,
        ),
        _session(
          'high',
          workspaceId: 'w1',
          tabId: 't2',
          cpuPercent: 9,
          memoryBytes: 90,
        ),
        _session(
          'absent',
          workspaceId: 'w1',
          tabId: 't3',
          measured: false,
          running: false,
        ),
      ], cpuCoreCount: cpuCoreCount),
      projects: <Project>[_project('p1', 'Alera')],
      workspaces: <Workspace>[_workspace('w1', 'Main')],
      tabs: <WorkspaceTabRecord>[
        _tab('t1', 'w1', sessionId: 'low', title: 'Bravo'),
        _tab('t2', 'w1', sessionId: 'high', title: 'Alpha'),
        _tab('t3', 'w1', sessionId: 'absent', title: 'Charlie'),
      ],
    );

    test('memory sorts descending with unmeasured rows last', () {
      final sessions = buildWithSort(
        ResourceSortColumn.memory,
      ).projects.single.workspaces.single.sessions;

      expect(sessions.map((session) => session.label), <String>[
        'Alpha',
        'Bravo',
        'Charlie',
      ]);
    });

    test('cpu sorts descending with unmeasured rows last', () {
      final sessions = buildWithSort(
        ResourceSortColumn.cpu,
      ).projects.single.workspaces.single.sessions;

      expect(sessions.last.label, 'Charlie');
      expect(sessions.first.label, 'Alpha');
    });

    test('the core count does not reorder the cpu column', () {
      // Dividing every row by the same number cannot change their order, so a
      // 16-core machine ranks terminals the same way a single-core one does.
      List<String> labels(int cores) => buildWithSort(
        ResourceSortColumn.cpu,
        cpuCoreCount: cores,
      ).projects.single.workspaces.single.sessions.map((s) => s.label).toList();

      expect(labels(16), labels(1));
    });

    test('name sorts alphabetically regardless of usage', () {
      final sessions = buildWithSort(
        ResourceSortColumn.name,
      ).projects.single.workspaces.single.sessions;

      expect(sessions.map((session) => session.label), <String>[
        'Alpha',
        'Bravo',
        'Charlie',
      ]);
    });

    test('projects and workspaces sort by their aggregate', () {
      final tree = buildResourceTree(
        snapshot: _snapshot(<ResourceSessionSample>[
          _session('s1', workspaceId: 'w1', tabId: 't1', memoryBytes: 10),
          _session('s2', workspaceId: 'w2', tabId: 't2', memoryBytes: 900),
        ]),
        projects: <Project>[_project('p1', 'Small'), _project('p2', 'Large')],
        workspaces: <Workspace>[
          _workspace('w1', 'Small workspace'),
          _workspace('w2', 'Large workspace', projectId: 'p2'),
        ],
        tabs: <WorkspaceTabRecord>[
          _tab('t1', 'w1', sessionId: 's1'),
          _tab('t2', 'w2', sessionId: 's2'),
        ],
      );

      expect(tree.projects.map((project) => project.name), <String>[
        'Large',
        'Small',
      ]);
    });
  });

  group('compareMetricDescending', () {
    test('absent values always sort last', () {
      expect(compareMetricDescending(null, 1), greaterThan(0));
      expect(compareMetricDescending(1, null), lessThan(0));
      expect(compareMetricDescending(null, null), 0);
    });

    test('larger values sort first', () {
      expect(compareMetricDescending(9, 1), lessThan(0));
      expect(compareMetricDescending(1, 9), greaterThan(0));
      expect(compareMetricDescending(5, 5), 0);
    });
  });
}
