import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_status_chip.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_status_panel.dart';
import 'package:flutter/material.dart';

const _history = <int>[120, 180, 160, 240, 300, 280, 420, 500];

ResourceSnapshot _snapshot({bool warming = false, String? error}) {
  return ResourceSnapshot(
    collectedAt: DateTime.utc(2026, 7, 25),
    warming: warming,
    host: const ResourceHostMetrics(
      totalMemoryBytes: 16 * 1024 * 1024 * 1024,
      availableMemoryBytes: 6 * 1024 * 1024 * 1024,
      usedMemoryBytes: 10 * 1024 * 1024 * 1024,
      memoryUsagePercent: 62.5,
      cpuCoreCount: 8,
      loadAverage1m: 2.4,
    ),
    hostProcess: const ResourceProcessSample(
      pid: 4100,
      cpuPercent: 1.2,
      memoryBytes: 42 * 1024 * 1024,
      processCount: 1,
      history: _history,
    ),
    appProcess: const ResourceProcessSample(
      pid: 4200,
      cpuPercent: 0.6,
      memoryBytes: 280 * 1024 * 1024,
      processCount: 1,
      history: _history,
    ),
    sessions: const <ResourceSessionSample>[],
    totalCpuPercent: 187.4,
    totalMemoryBytes: 1400 * 1024 * 1024,
    error: error,
  );
}

ResourceSessionRow _session(
  String label, {
  double? cpuPercent = 12.5,
  int? memoryBytes = 500 * 1024 * 1024,
  bool orphan = false,
}) => ResourceSessionRow(
  sessionId: 'session-$label',
  label: label,
  tabId: 'tab-$label',
  running: true,
  orphan: orphan,
  cpuPercent: cpuPercent,
  memoryBytes: memoryBytes,
  processCount: 7,
  history: _history,
);

ResourceTree _tree({
  List<ResourceSessionRow> orphans = const <ResourceSessionRow>[],
  bool remote = false,
}) => ResourceTree(
  projects: <ResourceProjectGroup>[
    ResourceProjectGroup(
      projectId: 'p1',
      name: 'Alera',
      workspaces: <ResourceWorkspaceRow>[
        ResourceWorkspaceRow(
          workspaceId: 'w1',
          name: 'Main',
          projectId: 'p1',
          remote: false,
          sessions: <ResourceSessionRow>[
            _session('Codex Agent'),
            _session('Build', cpuPercent: 3.1, memoryBytes: 90 * 1024 * 1024),
          ],
        ),
        if (remote)
          ResourceWorkspaceRow(
            workspaceId: 'w2',
            name: 'Mini PC',
            projectId: 'p1',
            remote: true,
            sessions: <ResourceSessionRow>[
              _session('Remote Shell', cpuPercent: null, memoryBytes: null),
            ],
          ),
      ],
    ),
  ],
  orphanSessions: orphans,
);

Widget _panel(
  ResourceSnapshot snapshot,
  ResourceTree tree, {
  bool host = false,
}) {
  return ResourceStatusPanel(
    snapshot: snapshot,
    tree: tree,
    sortColumn: ResourceSortColumn.memory,
    hostUnreachable: host,
    onSortColumnChanged: (_) {},
    onOpenSession: (_) {},
    onKillSession: (_) {},
    onKillOrphans: () {},
  );
}

@AleraPreview(name: 'Populated', group: 'Resource manager')
Widget resourceStatusPanelPopulatedPreview() => _panel(_snapshot(), _tree());

@AleraPreview(name: 'With Orphans', group: 'Resource manager')
Widget resourceStatusPanelOrphansPreview() => _panel(
  _snapshot(),
  _tree(
    orphans: <ResourceSessionRow>[
      _session('session-abc', orphan: true, cpuPercent: 0.2),
    ],
  ),
);

@AleraPreview(name: 'Remote Workspace', group: 'Resource manager')
Widget resourceStatusPanelRemotePreview() =>
    _panel(_snapshot(), _tree(remote: true));

@AleraPreview(name: 'Warming', group: 'Resource manager')
Widget resourceStatusPanelWarmingPreview() =>
    _panel(_snapshot(warming: true), ResourceTree.empty);

@AleraPreview(name: 'Host Unreachable', group: 'Resource manager')
Widget resourceStatusPanelUnreachablePreview() => _panel(
  _snapshot(error: 'The runtime host is not running.'),
  ResourceTree.empty,
  host: true,
);

@AleraPreview(name: 'Chip', group: 'Resource manager')
Widget resourceStatusChipPreview() => ResourceStatusChip(
  snapshot: _snapshot(),
  sessionCount: 7,
  orphanCount: 2,
  onPressed: () {},
);
