import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
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
  void Function(ActivityNavigation navigation)? navigate,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final runs = repository ?? FakeRunRepository();
  final container = runsContainer(runs);
  addTearDown(container.dispose);
  addTearDown(runs.dispose);
  final navigation = container.read(activityNavigationProvider.notifier)
    ..open();
  navigate?.call(navigation);
  await tester.pumpWidget(RunsTestApp(container: container));
  await tester.pumpAndSettle();
  return (container, runs);
}

Iterable<(String, Map<String, Object?>)> _calls(
  FakeRunRepository runs,
  String verb,
) => runs.calls.where((call) => call.$1 == verb);

void main() {
  testWidgets('the list groups runs and shows status, progress and age', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('ATTENTION (2)'), findsOneWidget);
    expect(find.text('ACTIVE (1)'), findsOneWidget);
    expect(find.text('HISTORY (1)'), findsOneWidget);
    expect(find.text('Add OAuth login to the settings page'), findsOneWidget);
    expect(find.text('Needs Attention · 4/9 · Stage gate'), findsOneWidget);
    expect(find.text('Needs Attention · 2/9 · Stalled task'), findsOneWidget);
    expect(find.text('Running · 1/9'), findsOneWidget);
    expect(find.text('Completed · 9/9'), findsOneWidget);
    expect(find.text('alera / feature-oauth'), findsNWidgets(4));
    expect(find.text('2h ago'), findsOneWidget);
    expect(find.text('20m ago'), findsOneWidget);
    expect(find.text('10m ago'), findsOneWidget);
    expect(find.text('1d ago'), findsOneWidget);
    expect(find.text('Select a Run'), findsOneWidget);
  });

  testWidgets('a host without runsV1 shows Update Required', (tester) async {
    final runs = FakeRunRepository()..error = const RunsUpdateRequired();
    await _pump(tester, repository: runs);
    expect(find.text('Update Required'), findsOneWidget);
    expect(
      find.textContaining('This host cannot provide runs safely'),
      findsOneWidget,
    );
  });

  testWidgets('a stage gate approves with its evidence digest', (tester) async {
    final (_, runs) = await _pump(
      tester,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    expect(find.text('STAGE GATE · foundation'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('gateOption:approve')));
    await tester.pumpAndSettle();
    final call = _calls(runs, 'runs.resolveGate').single.$2;
    expect(call['gateId'], 'gate-stage');
    expect(call['decision'], RunGateOptions.approve);
    expect(call['expectedEvidenceDigest'], 'digest-1');
    expect(call.containsKey('reason'), isFalse);
  });

  testWidgets('reject and request changes need notes', (tester) async {
    final (_, runs) = await _pump(
      tester,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    final requestChanges = find.byKey(
      const ValueKey<String>('gateOption:requestChanges'),
    );
    await tester.tap(requestChanges);
    await tester.pump();
    expect(_calls(runs, 'runs.resolveGate'), isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey<String>('gateNotes')),
      '  Split the provider work  ',
    );
    await tester.pump();
    await tester.tap(requestChanges);
    await tester.pumpAndSettle();
    final call = _calls(runs, 'runs.resolveGate').single.$2;
    expect(call['decision'], RunGateOptions.requestChanges);
    expect(call['reason'], 'Split the provider work');
  });

  testWidgets('a stale gate asks for a refresh before deciding', (
    tester,
  ) async {
    final runs = FakeRunRepository()
      ..mutationError = const TerminalHostConflictException(
        code: 'gate_stale',
        message: 'stale',
      );
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('gateOption:approve')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This gate changed while you were reading. Refresh before deciding.',
      ),
      findsOneWidget,
    );
    final approve = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('gateOption:approve')),
    );
    expect(approve.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey<String>('gateRefresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('gateOption:approve')));
    await tester.pumpAndSettle();
    final ids = _calls(
      runs,
      'runs.resolveGate',
    ).map((call) => call.$2['requestId']).toList();
    expect(ids, hasLength(2));
    expect(
      ids.toSet(),
      hasLength(2),
      reason: 'a stale decision is not replayed',
    );
  });

  for (final (kind, option, decision) in <(String, String, String)>[
    ('plan', 'approve', 'approve'),
    ('stall', 'killAndFailover', 'killAndFailover'),
    ('stall', 'keepWaiting', 'keepWaiting'),
    ('stall', 'abortStage', 'abortStage'),
    ('decision', '/oauth/github', '/oauth/github'),
  ]) {
    testWidgets('a $kind gate sends $decision', (tester) async {
      final runs = FakeRunRepository();
      runs.snapshots['run-1'] = runSnapshot(
        gates: <RunGate>[
          runGate(
            id: 'gate-$kind',
            kind: kind,
            taskId: kind == 'plan' ? null : 'task-2',
            question: kind == 'decision'
                ? 'Which OAuth callback path should the provider use?'
                : '',
            options: kind == 'decision'
                ? const <String>['/auth/callback/github', '/oauth/github']
                : null,
            evidenceDigest: kind == 'plan' ? 'plan-digest' : null,
          ),
        ],
      );
      await _pump(
        tester,
        repository: runs,
        navigate: (navigation) => navigation.selectRun('run-1'),
      );
      await tester.tap(find.byKey(ValueKey<String>('gateOption:$option')));
      await tester.pumpAndSettle();
      final call = _calls(runs, 'runs.resolveGate').single.$2;
      expect(call['gateId'], 'gate-$kind');
      expect(call['decision'], decision);
    });
  }

  testWidgets('a decision gate takes a free-text answer', (tester) async {
    final runs = FakeRunRepository();
    runs.snapshots['run-1'] = runSnapshot(
      gates: <RunGate>[
        runGate(
          id: 'gate-decision',
          kind: 'decision',
          taskId: 'task-2',
          question: 'Which callback path?',
          options: const <String>['/a', '/b'],
          evidenceDigest: null,
        ),
      ],
    );
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('gateOtherToggle')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('gateOtherField')),
      '/login/github',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('gateOption:__other__')),
    );
    await tester.pumpAndSettle();
    final call = _calls(runs, 'runs.resolveGate').single.$2;
    expect(call['decision'], '/login/github');
    expect(call.containsKey('reason'), isFalse);
  });

  testWidgets('Pause sends the sequence the run showed', (tester) async {
    final runs = FakeRunRepository();
    runs.snapshots['run-1'] = runSnapshot(
      run: runSummary(status: 'running', bucket: 'active'),
      gates: const <RunGate>[],
    );
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey<String>('runPause')));
    await tester.tap(find.byKey(const ValueKey<String>('runPause')));
    await tester.pumpAndSettle();
    final call = _calls(runs, 'runs.control').single.$2;
    expect(call['action'], 'pause');
    expect(call['expectedSequence'], 3);
  });

  testWidgets('Cancel Run asks first', (tester) async {
    final (_, runs) = await _pump(
      tester,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey<String>('runCancel')));
    await tester.tap(find.byKey(const ValueKey<String>('runCancel')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel Run?'), findsOneWidget);
    await tester.tap(find.text('Keep Running'));
    await tester.pumpAndSettle();
    expect(_calls(runs, 'runs.control'), isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('runCancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Run'));
    await tester.pumpAndSettle();
    expect(_calls(runs, 'runs.control').single.$2['action'], 'cancel');
  });

  testWidgets('a planning run shows the coordinator preparing its plan', (
    tester,
  ) async {
    final runs = FakeRunRepository();
    runs.snapshots['run-1'] = runSnapshot(
      run: runSummary(status: 'planning', bucket: 'active'),
      gates: const <RunGate>[],
      planState: null,
    );
    await _pump(
      tester,
      repository: runs,
      navigate: (navigation) => navigation.selectRun('run-1'),
    );
    expect(find.text('Coordinator is preparing a plan…'), findsOneWidget);
    expect(find.text('Open Coordinator Terminal'), findsOneWidget);
  });

  testWidgets('Tasks groups by stage and opens the inspector', (tester) async {
    final (container, runs) = await _pump(
      tester,
      navigate: (navigation) => navigation
        ..selectRun('run-1')
        ..showRunTab(RunDetailTab.tasks),
    );
    expect(find.text('FOUNDATION · 1/1 INTEGRATED · STAGE GATE'), findsNothing);
    expect(find.textContaining('FOUNDATION · 1/1 INTEGRATED'), findsOneWidget);
    expect(
      find.textContaining('IMPLEMENTATION · 0/2 INTEGRATED'),
      findsOneWidget,
    );
    await tester.tap(find.text('Implement GitHub provider'));
    await tester.pumpAndSettle();
    expect(container.read(activityNavigationProvider).runs.taskId, 'task-2');
    expect(find.text('STALL · implement-github'), findsOneWidget);
    expect(
      find.text('Worker-reported evidence is not an independent review.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('gateOption:killAndFailover')),
    );
    await tester.pumpAndSettle();
    expect(
      _calls(runs, 'runs.resolveGate').single.$2['decision'],
      'killAndFailover',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('runRetryTask')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('runRetryTask')));
    await tester.pumpAndSettle();
    expect(_calls(runs, 'runs.retryTask').single.$2['taskId'], 'task-2');
  });
}
