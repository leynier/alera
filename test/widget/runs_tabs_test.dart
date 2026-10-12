import 'package:alera/src/design_system/buttons/alera_tab_strip.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/runs/infra/recipe_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/runs_fake_repository.dart';
import '../support/runs_fixtures.dart';
import '../support/runs_harness.dart';

Future<(ProviderContainer, FakeRunRepository)> _pump(
  WidgetTester tester, {
  FakeRunRepository? repository,
  RunsTestWorkbench? workbench,
  void Function(ActivityNavigation navigation)? navigate,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final runs = repository ?? FakeRunRepository();
  final container = runsContainer(runs, workbench: workbench);
  addTearDown(container.dispose);
  addTearDown(runs.dispose);
  final navigation = container.read(activityNavigationProvider.notifier)
    ..open();
  navigate?.call(navigation);
  await tester.pumpWidget(RunsTestApp(container: container));
  await tester.pumpAndSettle();
  return (container, runs);
}

void main() {
  testWidgets('Timeline groups by day, filters and loads older events', (
    tester,
  ) async {
    final (container, runs) = await _pump(
      tester,
      navigate: (navigation) => navigation
        ..selectRun('run-1')
        ..showRunTab(RunDetailTab.timeline),
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Gate opened'), findsOneWidget);
    expect(
      find.text('Escalation · implement-github -> Coordinator'),
      findsOneWidget,
    );
    expect(find.text('YESTERDAY'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('I need the secret name before wiring the callback.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Load Older Events'));
    await tester.tap(find.text('Load Older Events'));
    await tester.pumpAndSettle();
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('Run created'), findsOneWidget);
    expect(
      runs.calls.where((call) => call.$1 == 'runs.timeline').last.$2['cursor'],
      '2026-09-30T13:35:00Z|e-3',
    );

    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    expect(
      container.read(activityNavigationProvider).runs.timelineFilter,
      RunTimelineFilter.messages,
    );
    expect(
      runs.calls.where((call) => call.$1 == 'runs.timeline').last.$2['kinds'],
      RunTimelineFilter.messages.kinds,
    );
    expect(find.text('Gate opened'), findsNothing);
  });

  testWidgets('Open Diff on a timeline entry opens its exact commit range', (
    tester,
  ) async {
    final runs = FakeRunRepository()
      ..timeline = RunTimelinePage(
        runId: 'run-1',
        items: <RunTimelineEntry>[
          RunTimelineEntry(
            id: 'e-integrated',
            source: 'event',
            kind: 'integrated',
            createdAt: '2026-09-30 13:58:00',
            taskId: 'task-1',
            workspaceId: 'ws-1',
            sha: 'b' * 40,
            baseSha: 'a' * 40,
          ),
          const RunTimelineEntry(
            id: 'e-elsewhere',
            source: 'event',
            kind: 'taskCompleted',
            createdAt: '2026-09-30 13:50:00',
            workspaceId: 'ws-gone',
            sha: 'c',
            baseSha: 'd',
          ),
          const RunTimelineEntry(
            id: 'e-paused',
            source: 'event',
            kind: 'paused',
            createdAt: '2026-09-30 13:40:00',
          ),
        ],
      );
    final workbench = RunsTestWorkbench();
    final (container, _) = await _pump(
      tester,
      repository: runs,
      workbench: workbench,
      navigate: (navigation) => navigation
        ..selectRun('run-1')
        ..showRunTab(RunDetailTab.timeline),
    );
    expect(find.text('Integrated'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('runTimelineDiff:e-elsewhere')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('runTimelineDiff:e-paused')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('runTimelineDiff:e-integrated')),
    );
    await tester.pumpAndSettle();
    expect(workbench.actions, <String>[
      'workspace:ws-1',
      'commitDiff:ws-1:${'a' * 40}..${'b' * 40}:Integrated result',
    ]);
    expect(container.read(activityNavigationProvider).visible, isFalse);
  });

  testWidgets('Task rows show their age and Resources its retained count', (
    tester,
  ) async {
    final runs = FakeRunRepository();
    final snapshot = runSnapshot();
    runs.snapshots['run-1'] = snapshot.copyWith(
      resourceCount: 3,
      tasks: <RunTask>[
        // SQLite stamps UTC without a zone; 13:10 is an hour before now.
        snapshot.tasks.first.copyWith(updatedAt: '2026-09-30 13:10:00'),
        ...snapshot.tasks.skip(1),
      ],
    );
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation
        ..selectRun('run-1')
        ..showRunTab(RunDetailTab.tasks),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('task-1')),
        matching: find.text('1h ago'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('task-2')),
        matching: find.textContaining('ago'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AleraTabStrip<RunDetailTab>),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    runs.snapshots['run-1'] = snapshot.copyWith(resourceCount: 0);
    runs.changed();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AleraTabStrip<RunDetailTab>),
        matching: find.text('0'),
      ),
      findsNothing,
    );
  });

  testWidgets('Resolve on an open gate focuses it on Overview', (tester) async {
    final (container, _) = await _pump(
      tester,
      navigate: (navigation) => navigation
        ..selectRun('run-1')
        ..showRunTab(RunDetailTab.timeline),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('runTimelineResolve:gate-stage')),
    );
    await tester.pumpAndSettle();
    final runs = container.read(activityNavigationProvider).runs;
    expect(runs.tab, RunDetailTab.overview);
    expect(runs.gateId, 'gate-stage');
    expect(find.text('STAGE GATE · foundation'), findsOneWidget);
  });

  testWidgets('Resources previews a selection and applies it confirmed', (
    tester,
  ) async {
    final runs = FakeRunRepository();
    runs.snapshots['run-1'] = runSnapshot(
      run: runSummary(
        status: 'completed',
        bucket: 'history',
        pendingGateKinds: const <String>[],
        completedAt: '2026-09-30T12:00:00Z',
      ),
      gates: const [],
    );
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation
        ..selectRun('run-1')
        ..showRunTab(RunDetailTab.resources),
    );
    expect(
      find.text(
        'Retained worktrees and branches stay until you clean up. Selecting removes nothing until you confirm a preview.',
      ),
      findsOneWidget,
    );
    expect(find.text('0/25 selected'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('runCleanupSelect:workspace')),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/25 selected'), findsOneWidget);
    expect(find.text('Also Delete This Branch'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('runCleanupPreview')));
    await tester.pumpAndSettle();
    final preview = runs.calls.singleWhere(
      (call) => call.$1 == 'runs.previewCleanup',
    );
    expect(preview.$2['resources'], <String, bool>{'workspace': false});
    final apply = find.byKey(const ValueKey<String>('runCleanupApply'));
    await tester.ensureVisible(apply);
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey<String>('runCleanupConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(runs.calls.map((call) => call.$1), contains('runs.applyCleanup'));
    expect(find.text('Cleanup Complete'), findsOneWidget);
  });

  testWidgets('Resources stays hidden for shared runs', (tester) async {
    final runs = FakeRunRepository();
    runs.snapshots['run-1'] = runSnapshot(run: runSummary(isolation: 'shared'));
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    expect(
      find.byKey(const ValueKey<String>('aleraTab:Resources')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('aleraTab:Timeline')),
      findsOneWidget,
    );
  });

  testWidgets('New Run sends an isolated run with its recipe and roles', (
    tester,
  ) async {
    final (container, runs) = await _pumpWithRecipes(tester);
    await _openNewRun(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('newRunObjective')),
      'Add OAuth login',
    );
    await _choose(tester, 'newRunWorkspace', 'alera / feature-oauth');
    expect(find.text('Source commit a1b2c3d.'), findsOneWidget);
    expect(find.text('Freeform (Built-in)'), findsOneWidget);
    await _choose(tester, 'newRunCoordinator', 'Codex Sol (codex)');
    await tester.tap(find.byKey(const ValueKey<String>('newRunCreate')));
    await tester.pumpAndSettle();
    final create = runs.calls.singleWhere((call) => call.$1 == 'runs.create');
    expect(create.$2['isolation'], 'isolated');
    expect(create.$2['workspaceId'], 'ws-1');
    expect(create.$2['objective'], 'Add OAuth login');
    expect(create.$2['recipeSource'], <String, Object?>{
      'origin': 'builtIn',
      'id': 'freeform',
    });
    expect(create.$2['roleProfiles'], <String, String>{'worker': 'codex-sol'});
    expect(create.$2['coordinatorProfileId'], 'codex-sol');
    expect(create.$2['maxConcurrent'], 4);
    expect(create.$2['approvalRequired'], isFalse);
    expect(create.$2.containsKey('workerProfileId'), isFalse);
    expect(container.read(activityNavigationProvider).runs.runId, 'run-new');
    expect(find.byKey(const ValueKey<String>('newRunCreate')), findsNothing);
  });

  testWidgets('New Run sends a shared run with one worker profile', (
    tester,
  ) async {
    final (_, runs) = await _pumpWithRecipes(tester);
    await _openNewRun(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('newRunObjective')),
      'Fix flaky tests',
    );
    await tester.tap(find.text('Shared'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('newRunTemplate')), findsNothing);
    await _choose(tester, 'newRunWorkspace', 'educup / ci-migration');
    await _choose(tester, 'newRunCoordinator', 'Codex Sol (codex)');
    await _choose(tester, 'newRunWorker', 'Cursor (cursor)');
    await tester.tap(find.byKey(const ValueKey<String>('newRunApproval')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('newRunCreate')));
    await tester.pumpAndSettle();
    final create = runs.calls.singleWhere((call) => call.$1 == 'runs.create');
    expect(create.$2, <String, Object?>{
      'requestId': create.$2['requestId'],
      'workspaceId': 'ws-2',
      'objective': 'Fix flaky tests',
      'isolation': 'shared',
      'coordinatorProfileId': 'codex-sol',
      'workerProfileId': 'cursor',
      'maxConcurrent': 4,
      'approvalRequired': true,
    });
  });
}

Future<(ProviderContainer, FakeRunRepository)> _pumpWithRecipes(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final runs = FakeRunRepository();
  final container = runsContainer(runs, recipes: _Recipes());
  addTearDown(container.dispose);
  addTearDown(runs.dispose);
  container.read(activityNavigationProvider.notifier).open();
  await tester.pumpWidget(RunsTestApp(container: container));
  await tester.pumpAndSettle();
  return (container, runs);
}

Future<void> _openNewRun(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('activityPrimaryAction')));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String field, String label) async {
  await tester.tap(find.byKey(ValueKey<String>(field)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _Recipes extends RecipeRepository {
  _Recipes() : super(_NoClient());

  @override
  Future<Map<String, Object?>> list(String? workspaceId) async =>
      <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'source': <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
            'name': 'Freeform',
            'description': 'One stage, one role, no stage gates.',
          },
          <String, Object?>{
            'source': <String, Object?>{
              'origin': 'builtIn',
              'id': 'feature-delivery',
            },
            'name': 'Feature Delivery',
            'description': 'Foundation, implementation and product stages.',
          },
        ],
        'projectError': null,
      };

  @override
  Future<Map<String, Object?>> read(Map<String, Object?> source) async =>
      <String, Object?>{
        'source': source,
        'digest': 'digest',
        'recipe': <String, Object?>{
          'id': source['id'],
          'roles': <Object?>[
            <String, Object?>{'id': 'worker', 'name': 'Worker'},
          ],
        },
      };
}

class _NoClient implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) => throw UnimplementedError(type);
}
