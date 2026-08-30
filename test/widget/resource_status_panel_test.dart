import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_status_chip.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ResourceSnapshot _snapshot({bool warming = false, String? error}) =>
    ResourceSnapshot(
      collectedAt: .utc(2026, 7, 25),
      warming: warming,
      host: const ResourceHostMetrics(
        totalMemoryBytes: 16 * 1024 * 1024 * 1024,
        availableMemoryBytes: 6 * 1024 * 1024 * 1024,
        usedMemoryBytes: 10 * 1024 * 1024 * 1024,
        memoryUsagePercent: 62.5,
        cpuCoreCount: 8,
        loadAverage1m: 2.4,
      ),
      // Per-core percentages, the unit the host sends. The app row is busier
      // than a whole core, which is the case the panel has to normalize.
      hostProcess: const ResourceProcessSample(
        pid: 4100,
        cpuPercent: 4,
        memoryBytes: 42 * 1024 * 1024,
        processCount: 1,
        history: <int>[1, 2, 3],
      ),
      appProcess: const ResourceProcessSample(
        pid: 4200,
        cpuPercent: 96,
        memoryBytes: 280 * 1024 * 1024,
        processCount: 1,
        history: <int>[1, 2, 3],
      ),
      sessions: const <ResourceSessionSample>[],
      totalCpuPercent: 12.5,
      totalMemoryBytes: 1024 * 1024 * 1024,
      error: error,
    );

ResourceSessionRow _session(
  String label, {
  bool orphan = false,
  double? cpuMachinePercent = 12.5,
  int? memoryBytes = 500 * 1024 * 1024,
}) => ResourceSessionRow(
  sessionId: 'session-$label',
  label: label,
  tabId: 'tab-$label',
  running: true,
  orphan: orphan,
  cpuMachinePercent: cpuMachinePercent,
  memoryBytes: memoryBytes,
  processCount: 3,
  history: const <int>[1, 2, 3],
);

ResourceTree _tree({
  List<ResourceSessionRow> sessions = const <ResourceSessionRow>[],
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
          remote: remote,
          sessions: sessions,
        ),
      ],
    ),
  ],
  orphanSessions: orphans,
);

Future<void> _pump(
  WidgetTester tester, {
  required ResourceSnapshot snapshot,
  required ResourceTree tree,
  ResourceSortColumn sortColumn = ResourceSortColumn.memory,
  ValueChanged<ResourceSortColumn>? onSortColumnChanged,
  ValueChanged<ResourceSessionRow>? onOpenSession,
  ValueChanged<ResourceSessionRow>? onKillSession,
  VoidCallback? onKillOrphans,
  bool hostUnreachable = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: aleraDarkTheme,
      home: Scaffold(
        body: Center(
          child: ResourceStatusPanel(
            snapshot: snapshot,
            tree: tree,
            sortColumn: sortColumn,
            hostUnreachable: hostUnreachable,
            onSortColumnChanged: onSortColumnChanged ?? (_) {},
            onOpenSession: onOpenSession ?? (_) {},
            onKillSession: onKillSession ?? (_) {},
            onKillOrphans: onKillOrphans ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the project, workspace and session tree', (
    tester,
  ) async {
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(sessions: <ResourceSessionRow>[_session('Codex Agent')]),
    );

    expect(find.text('Resource Manager'), findsOneWidget);
    expect(find.text('Alera'), findsWidgets);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Codex Agent'), findsOneWidget);
    // The same reading appears on the session row and on the workspace and
    // project aggregates above it.
    expect(find.text('500.0 MB'), findsNWidgets(3));
    expect(find.text('12.5%'), findsWidgets);
    // The app and sidecar get their own rows, apart from the workspace tree.
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Runtime Host'), findsOneWidget);
  });

  testWidgets('the metric columns line up on rows with a close action', (
    tester,
  ) async {
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(sessions: <ResourceSessionRow>[_session('Codex Agent')]),
    );

    // Only the session row carries the close button; the aggregates above it
    // and the sort header do not, so this is what the reserved action slot has
    // to keep in one column. The totals strip carries a 'Memory' label too, so
    // anchor on the sort header's own button.
    final headerRight = tester
        .getTopRight(
          find.descendant(
            of: find.byTooltip('Sort By Memory'),
            matching: find.text('Memory'),
          ),
        )
        .dx;
    for (final cell in find.text('500.0 MB').evaluate()) {
      expect(tester.getTopRight(find.byWidget(cell.widget)).dx, headerRight);
    }
    // The action itself lives past the columns, inside the reserved slot.
    expect(
      tester.getTopRight(find.byTooltip('Close Terminal Session')).dx,
      greaterThan(headerRight),
    );
  });

  testWidgets('cpu is shown as a share of the machine, not of one core', (
    tester,
  ) async {
    // Eight cores, an app burning 96% of one of them and a sidecar at 4%.
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(
        sessions: <ResourceSessionRow>[
          _session('Codex Agent', cpuMachinePercent: 3),
        ],
      ),
    );

    // 96% of one core is 12% of the machine, never "96%" next to a memory
    // column that already reads as a share of the machine.
    expect(find.text('12.0%'), findsOneWidget);
    expect(find.text('0.5%'), findsOneWidget);
    // The Alera group row sums the two before normalizing.
    expect(find.text('12.5%'), findsOneWidget);
    // The totals strip: 12.5% of one core across eight of them.
    expect(find.text('1.6%'), findsOneWidget);
    expect(find.text('96.0%'), findsNothing);
  });

  testWidgets('a remote session shows a dash instead of zero', (tester) async {
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(
        remote: true,
        sessions: <ResourceSessionRow>[
          _session('Remote Shell', cpuMachinePercent: null, memoryBytes: null),
        ],
      ),
    );

    expect(find.text('remote'), findsOneWidget);
    // A dash for the session's CPU and memory, plus the workspace aggregate.
    expect(find.text('-'), findsWidgets);
    expect(find.text('0.0%'), findsNothing);
  });

  testWidgets('a warming snapshot does not report totals as zero', (
    tester,
  ) async {
    await _pump(tester, snapshot: _snapshot(warming: true), tree: .empty);

    expect(find.text('Measuring resource usage'), findsOneWidget);
    expect(find.text('0.0%'), findsNothing);
  });

  testWidgets('an unreachable host points at the host chip', (tester) async {
    await _pump(
      tester,
      snapshot: _snapshot(error: 'connection refused'),
      tree: .empty,
      hostUnreachable: true,
    );

    expect(
      find.textContaining('runtime host is not responding'),
      findsOneWidget,
    );
    // The error itself is surfaced rather than a generic empty state.
    expect(find.text('connection refused'), findsOneWidget);
  });

  testWidgets('orphans are listed apart with a kill-all action', (
    tester,
  ) async {
    var killedAll = false;
    ResourceSessionRow? killed;
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(
        sessions: <ResourceSessionRow>[_session('Codex Agent')],
        orphans: <ResourceSessionRow>[_session('stray', orphan: true)],
      ),
      onKillOrphans: () => killedAll = true,
      onKillSession: (session) => killed = session,
    );

    expect(find.text('Unattributed Terminals'), findsOneWidget);
    expect(find.text('1 orphan terminal'), findsOneWidget);

    await tester.tap(find.text('Kill All'));
    await tester.pump();
    expect(killedAll, isTrue);

    await tester.tap(find.byTooltip('Kill Orphan Terminal'));
    await tester.pump();
    expect(killed?.sessionId, 'session-stray');
  });

  testWidgets('tapping a session row opens it', (tester) async {
    ResourceSessionRow? opened;
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(sessions: <ResourceSessionRow>[_session('Codex Agent')]),
      onOpenSession: (session) => opened = session,
    );

    await tester.tap(find.text('Codex Agent'));
    await tester.pump();

    expect(opened?.sessionId, 'session-Codex Agent');
  });

  testWidgets('the sort header reports the selected column', (tester) async {
    ResourceSortColumn? selected;
    await _pump(
      tester,
      snapshot: _snapshot(),
      tree: _tree(sessions: <ResourceSessionRow>[_session('Codex Agent')]),
      onSortColumnChanged: (column) => selected = column,
    );

    await tester.tap(find.byTooltip('Sort By CPU'));
    await tester.pump();

    expect(selected, ResourceSortColumn.cpu);
  });

  testWidgets('the chip shows memory, session count and orphans', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: ResourceStatusChip(
            snapshot: _snapshot(),
            sessionCount: 7,
            orphanCount: 2,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('1.00 GB'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
  });

  testWidgets('the chip hides the orphan count when there are none', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: ResourceStatusChip(
            snapshot: _snapshot(),
            sessionCount: 1,
            orphanCount: 0,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('(0)'), findsNothing);
  });
}
