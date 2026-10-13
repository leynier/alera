import 'package:alchemist/alchemist.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/presentation/activity_page.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/presentation/new_run_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/runs_fake_repository.dart';
import '../support/runs_fixtures.dart';
import '../support/runs_harness.dart';
import 'alera_golden_harness.dart';

typedef _Scenario = ({
  String name,
  double width,
  double height,
  double scale,
  void Function(FakeRunRepository runs) seed,
  void Function(ActivityNavigation navigation) navigate,
  bool dialog,
});

void _none(FakeRunRepository runs) {}

final List<_Scenario> _scenarios = <_Scenario>[
  (
    name: 'runs_list_overview',
    width: 1300,
    height: 900,
    scale: 1,
    seed: _none,
    navigate: (navigation) => navigation.selectRun('run-1'),
    dialog: false,
  ),
  (
    name: 'runs_gate_cards',
    width: 1300,
    height: 1500,
    scale: 1,
    seed: (runs) => runs.snapshots['run-1'] = runSnapshot(
      gates: <RunGate>[
        runGate(
          id: 'gate-plan',
          kind: 'plan',
          question:
              'The coordinator proposed 9 tasks in 3 stages from a1b2c3d.',
          evidenceDigest: 'plan-digest',
          createdAt: '2026-09-30T14:05:00Z',
        ),
        runGate(createdAt: '2026-09-30T14:00:00Z'),
        runGate(
          id: 'gate-decision',
          kind: 'decision',
          taskId: 'task-2',
          question: 'Which OAuth callback path should the provider use?',
          options: const <String>['/auth/callback/github', '/oauth/github'],
          evidenceDigest: null,
          createdAt: '2026-09-30T13:58:00Z',
        ),
        runGate(
          id: 'gate-stall',
          kind: 'stall',
          taskId: 'task-2',
          evidenceDigest: null,
          createdAt: '2026-09-30T13:50:00Z',
        ),
      ],
    ),
    navigate: (navigation) => navigation.selectRun('run-1'),
    dialog: false,
  ),
  (
    name: 'runs_task_inspector',
    width: 1300,
    height: 1100,
    scale: 1,
    seed: _none,
    navigate: (navigation) => navigation
      ..selectRun('run-1')
      ..selectTask('task-2'),
    dialog: false,
  ),
  (
    name: 'runs_tasks',
    width: 1300,
    height: 800,
    scale: 1,
    seed: _none,
    navigate: (navigation) => navigation
      ..selectRun('run-1')
      ..showRunTab(RunDetailTab.tasks),
    dialog: false,
  ),
  (
    name: 'runs_timeline',
    width: 1300,
    height: 800,
    scale: 1,
    seed: _none,
    navigate: (navigation) => navigation
      ..selectRun('run-1')
      ..showRunTab(RunDetailTab.timeline),
    dialog: false,
  ),
  (
    name: 'runs_resources',
    width: 1300,
    height: 800,
    scale: 1,
    seed: (runs) => runs.snapshots['run-1'] = runSnapshot(
      run: runSummary(
        status: 'completed',
        bucket: 'history',
        pendingGateKinds: const <String>[],
        completedAt: '2026-09-30T12:00:00Z',
      ),
      gates: const <RunGate>[],
    ),
    navigate: (navigation) => navigation
      ..selectRun('run-1')
      ..showRunTab(RunDetailTab.resources),
    dialog: false,
  ),
  (
    name: 'runs_compact_scaled',
    width: 420,
    height: 900,
    scale: 2,
    seed: _none,
    navigate: (navigation) => navigation.selectRun('run-1'),
    dialog: false,
  ),
  (
    name: 'runs_update_required',
    width: 1000,
    height: 640,
    scale: 1,
    seed: (runs) => runs.error = const RunsUpdateRequired(),
    navigate: (navigation) {},
    dialog: false,
  ),
  (
    name: 'runs_new_run_dialog',
    width: 760,
    height: 900,
    scale: 1,
    seed: _none,
    navigate: (navigation) {},
    dialog: true,
  ),
];

void main() {
  runAleraGoldenTests(() {
    for (final scenario in _scenarios) {
      goldenTest(
        scenario.name,
        fileName: scenario.name,
        constraints: BoxConstraints.tightFor(
          width: scenario.width,
          height: scenario.height,
        ),
        pumpBeforeTest: (tester) async {
          await tester.pumpAndSettle();
        },
        builder: () {
          final runs = FakeRunRepository();
          scenario.seed(runs);
          final container = runsContainer(runs);
          addTearDown(container.dispose);
          addTearDown(runs.dispose);
          final navigation = container.read(activityNavigationProvider.notifier)
            ..open();
          scenario.navigate(navigation);
          return UncontrolledProviderScope(
            container: container,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: Material(
                  child: scenario.dialog
                      ? const NewRunDialog()
                      : const ActivityPage(),
                ),
              ),
            ),
          );
        },
      );
    }
  });
}
