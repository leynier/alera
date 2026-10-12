import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/application/activity_notifications.dart';
import 'package:alera/src/features/activity/application/run_attention_link.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/runs/application/run_actions.dart';
import 'package:alera/src/features/runs/application/run_board_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/application/run_timeline_page.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:alera/src/features/runs/presentation/run_timeline_tab.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/runs_fake_repository.dart';
import '../support/runs_fixtures.dart';

ProviderContainer _container(FakeRunRepository runs) {
  final container = ProviderContainer(
    overrides: [
      runRepositoryProvider.overrideWithValue(runs),
      appForegroundProvider.overrideWithValue(const AlwaysForeground()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(runs.dispose);
  return container;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('status labels', () {
    test('runs', () {
      RunStatusLabel label(String status, {String bucket = 'active'}) =>
          runStatusLabel(
            runSummary(
              status: status,
              bucket: bucket,
              completedAt: status == 'cancelled' ? null : '2026-09-30',
            ),
          );
      expect(label('planning').label, 'Planning');
      expect(label('awaitingApproval').label, 'Plan Awaiting Approval');
      expect(label('awaitingApproval').tone, AleraBadgeTone.attention);
      expect(label('paused').label, 'Paused');
      expect(label('running').label, 'Running');
      expect(label('running').tone, AleraBadgeTone.info);
      expect(label('running', bucket: 'attention').label, 'Needs Attention');
      expect(label('completed').tone, AleraBadgeTone.success);
      expect(label('failed').tone, AleraBadgeTone.error);
      expect(label('cancelled').label, 'Cancelling');
      expect(
        runStatusLabel(
          runSummary(
            status: 'cancelled',
            bucket: 'history',
            completedAt: '2026-09-30',
          ),
        ).label,
        'Cancelled',
      );
    });

    test('tasks and gates', () {
      expect(taskStatusLabel('pending').label, 'Queued');
      expect(taskStatusLabel('dispatched').label, 'Running');
      expect(taskStatusLabel('result_ready').label, 'Result Ready');
      expect(taskStatusLabel('integrated').tone, AleraBadgeTone.success);
      expect(taskStatusLabel('stalled').tone, AleraBadgeTone.attention);
      expect(taskStatusLabel('refused').label, 'Needs Correction');
      expect(taskStatusLabel('conflict').tone, AleraBadgeTone.error);
      expect(runGateKindLabel(RunGateKind.plan), 'Plan Approval');
      expect(runGateKindLabel(RunGateKind.stage), 'Stage Gate');
      expect(runGateStatusLabel(RunGateStatus.timeout).label, 'Expired');
      expect(runGateStatusLabel(RunGateStatus.pending).label, 'Pending');
    });

    test('ages and days', () {
      expect(runAgeLabel('2026-09-30T14:06:00Z', runsTestNow), '4m ago');
      expect(runAgeLabel('2026-09-30T12:10:00Z', runsTestNow), '2h ago');
      expect(
        runDayLabel(DateTime.utc(2026, 9, 30, 9), runsTestNow.toLocal()),
        'Today',
      );
    });
  });

  group('timeline labels', () {
    const kinds = <String>[
      'created', 'coordinatorStarted', 'planProposed', 'planApproved', //
      'planRejected', 'changesRequested', 'taskCreated', 'attemptPrepared',
      'dispatched', 'accepted', 'escalation', 'taskCompleted', 'taskFailed',
      'taskStalled', 'taskCancelled', 'gateOpened', 'gateResolved',
      'integrationStarted', 'integrated', 'conflict', 'attention', 'retried',
      'paused', 'resumed', 'cancelled', 'completed', 'failed',
      'cleanupPrepared', 'cleanupApplied', 'cleanupAbandoned',
    ];

    test('every event kind has a sentence case label', () {
      for (final kind in kinds) {
        final label = runEventLabel(kind);
        expect(label, isNot(kind), reason: kind);
        expect(label[0], label[0].toUpperCase(), reason: kind);
        expect(
          label.split(' ').skip(1).where((word) => word != word.toLowerCase()),
          isEmpty,
          reason: kind,
        );
      }
    });

    test('an escalation event reads like its message', () {
      final entry = timelineEntry(
        id: 'e-escalation',
        kind: 'escalation',
        createdAt: '2026-09-30 13:58:00',
        summary: 'The secret is missing',
        from: 'w-3',
        to: 'coordinator-1',
        body: 'Set OAUTH_SECRET.',
        messageType: 'escalation',
      );
      expect(entry.carriesMessage, isTrue);
      expect(
        runTimelineTitle(entry, const <String, String>{}),
        startsWith('Escalation · '),
      );
      expect(
        runTimelineTitle(
          timelineEntry(id: 'e-1', kind: 'escalation', createdAt: ''),
          const <String, String>{},
        ),
        'Escalation',
      );
    });
  });

  test('focusGate opens Runs on the run Overview at that gate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier)
      ..selectRun('run-2')
      ..selectTask('task-1');
    navigation.focusGate('run-1', 'gate-1');
    final location = container.read(activityNavigationProvider);
    expect(location.showing(ActivitySection.runs), isTrue);
    expect(location.runs.runId, 'run-1');
    expect(location.runs.tab, RunDetailTab.overview);
    expect(location.runs.taskId, isNull);
    expect(location.runs.gateId, 'gate-1');
    final sequence = location.runs.gateFocusSequence;
    navigation.focusGate('run-1', 'gate-1');
    expect(
      container.read(activityNavigationProvider).runs.gateFocusSequence,
      sequence + 1,
    );
  });

  test('the timeline appends older pages and keeps them on refresh', () async {
    final runs = FakeRunRepository();
    final container = _container(runs);
    final provider = runTimelineProvider('run-1', RunTimelineFilter.all);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();
    expect(container.read(provider).value!.data.items, hasLength(4));
    await container.read(provider.notifier).loadOlder();
    final loaded = container.read(provider).value!.data;
    expect(loaded.items.map((entry) => entry.id), <String>[
      'e-5',
      'e-escalation',
      'e-4',
      'e-3',
      'e-2',
      'e-1',
    ]);
    expect(loaded.nextCursor, isNull);
    runs.changed();
    await _settle();
    expect(container.read(provider).value!.data.items, hasLength(6));
  });

  test('the timeline filter sends its kinds', () async {
    final runs = FakeRunRepository();
    final container = _container(runs);
    final provider = runTimelineProvider('run-1', RunTimelineFilter.gates);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();
    expect(runs.calls.last.$2['kinds'], RunTimelineFilter.gates.kinds);
    expect(
      container.read(provider).value!.data.items.map((entry) => entry.kind),
      <String>['gateOpened'],
    );
  });

  test('a lost gate response replays the same request id', () async {
    final runs = FakeRunRepository()..mutationError = StateError('Lost');
    final container = _container(runs);
    final actions = container.read(runActionsProvider.notifier);
    final gate = runGate();
    expect(await actions.resolveGate(gate, RunGateOptions.approve), isFalse);
    expect(
      container.read(runActionsProvider).errorFor(RunActions.gateKey(gate.id)),
      isA<StateError>(),
    );
    expect(await actions.resolveGate(gate, RunGateOptions.approve), isTrue);
    final ids = runs.calls.map((call) => call.$2['requestId']).toList();
    expect(ids, hasLength(2));
    expect(ids.toSet(), hasLength(1));
    expect(
      container.read(runActionsProvider).errorFor(RunActions.gateKey(gate.id)),
      isNull,
    );
  });

  test('a stale gate is flagged and its decision is not replayed', () async {
    final runs = FakeRunRepository()
      ..mutationError = const TerminalHostConflictException(
        code: 'gate_stale',
        message: 'stale',
      );
    final container = _container(runs);
    final actions = container.read(runActionsProvider.notifier);
    final gate = runGate();
    await actions.resolveGate(gate, RunGateOptions.approve);
    expect(container.read(runActionsProvider).isStale(gate.id), isTrue);
    actions.clearGate(gate.id);
    expect(container.read(runActionsProvider).isStale(gate.id), isFalse);
    await actions.resolveGate(gate, RunGateOptions.approve);
    final ids = runs.calls.map((call) => call.$2['requestId']).toSet();
    expect(ids, hasLength(2));
  });

  test('the attention board feeds the chip count and hover rows', () async {
    final runs = FakeRunRepository();
    final container = _container(runs);
    final subscription = container.listen(runBoardAttentionProvider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();
    final page = container.read(runBoardAttentionProvider).value!;
    expect(page.counts.attention, 2);
    expect(
      page.items.every((run) => run.bucket == RunBucket.attention),
      isTrue,
    );
    expect(runs.calls.first.$2['bucket'], 'attention');
  });

  group('run notifications', () {
    test('only growth while Activity is not watched notifies', () {
      final tracker = RunAttentionNotificationTracker();
      final first = runsBoardPage();
      expect(tracker.observe(first, activityVisible: false), isNull);
      final grown = first.copyWith(
        counts: const RunBoardCounts(attention: 3),
        items: <RunSummary>[
          runSummary(
            id: 'run-9',
            status: 'awaitingApproval',
            pendingGateKinds: const <String>['plan'],
            planGatePending: true,
          ),
          ...first.items,
        ],
      );
      expect(tracker.observe(grown, activityVisible: true), isNull);
      final more = grown.copyWith(
        counts: const RunBoardCounts(attention: 4),
        items: <RunSummary>[
          runSummary(id: 'run-10'),
          ...grown.items,
        ],
      );
      final run = tracker.observe(more, activityVisible: false);
      expect(run?.id, 'run-10');
      final notification = runAttentionNotification(run!);
      expect(notification.title, 'Run Needs Attention');
      expect(notification.body, 'A gate is waiting for your decision.');
      expect(decodeRunNotificationPayload(notification.payload), (
        runId: 'run-10',
        gateId: null,
      ));
      expect(
        runAttentionNotification(grown.items.first).body,
        'A plan is waiting for your approval.',
      );
      expect(decodeRunNotificationPayload('{"kind":"inboxReply"}'), isNull);
    });

    test('a board row that names its gate links the notification to it', () {
      final run = runSummary(
        id: 'run-11',
        pendingGateKinds: const <String>['plan', 'decision'],
        pendingGates: const <Map<String, Object?>>[
          <String, Object?>{'id': 'gate-plan', 'kind': 'plan'},
          <String, Object?>{
            'id': 'gate-decision',
            'kind': 'decision',
            'taskId': 'task-1',
          },
        ],
      );
      expect(run.pendingGates.last.taskId, 'task-1');
      final notification = runAttentionNotification(run);
      expect(notification.body, 'A plan is waiting for your approval.');
      expect(decodeRunNotificationPayload(notification.payload), (
        runId: 'run-11',
        gateId: 'gate-plan',
      ));
    });

    test('a named gate opens without reading the run gates', () async {
      final repository = FakeRunRepository();
      addTearDown(repository.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final navigation = container.read(activityNavigationProvider.notifier);
      await openRunAttention(
        repository,
        navigation,
        'run-1',
        gateId: 'gate-plan',
      );
      expect(
        container.read(activityNavigationProvider).runs.gateId,
        'gate-plan',
      );
      expect(repository.calls, isEmpty);
      await openRunAttention(repository, navigation, 'run-1');
      expect(repository.calls.single.$1, 'runs.gates');
    });
  });
}
