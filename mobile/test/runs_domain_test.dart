import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:alera_mobile/src/features/push_notifications/presentation/push_intent_router.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_new_run_form.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_actions.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_cleanup.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/domain/new_run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/infra/mobile_runtime_run_repository.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_runs_client.dart';

ProviderContainer _container(FakeRunsClient client) {
  final container = ProviderContainer(
    overrides: [
      mobileRunsClientProvider('host').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('parses a run summary and labels it with the shared vocabulary', () {
    final run = RunSummary.fromJson(
      runSummaryJson(
        status: 'paused',
        bucket: 'attention',
        pendingGateCount: 1,
      ),
    );
    expect(run.bucket, RunBucket.attention);
    expect(run.isolation, RunIsolation.isolated);
    expect(run.workspaceLabel, 'alera / feature-oauth');
    expect(runStatusLabel(run).label, 'Needs Attention');
    expect(runAttentionSummary(run), '1 gate');
    expect(
      runStatusLabel(RunSummary.fromJson(runSummaryJson(status: 'cancelled')))
          .label,
      'Cancelling',
    );
    expect(
      runStatusLabel(
        RunSummary.fromJson(runSummaryJson(status: 'awaitingApproval')),
      ).label,
      'Plan Awaiting Approval',
    );
    expect(
      runTaskStatusLabel('dispatched', attemptState: 'result_ready').label,
      'Result Ready',
    );
    expect(
      runTaskStatusLabel('failed', attemptState: 'started').label,
      'Failed',
    );
    expect(runTaskStatusLabel('pending').label, 'Queued');
  });

  test('gates always offer the runtime option ids for their kind', () {
    final stage = RunGate.fromJson(runGateJson(options: const <String>[]));
    final stall = RunGate.fromJson(runGateJson(kind: 'stall'));
    final decision = RunGate.fromJson(
      runGateJson(kind: 'decision', options: <String>['yes', 'no']),
    );
    expect(stage.choices, <String>['approve', 'requestChanges', 'reject']);
    expect(stall.choices, <String>[
      'killAndFailover',
      'keepWaiting',
      'abortStage',
    ]);
    expect(decision.choices, <String>['yes', 'no']);
    expect(RunGate.requiresReason('reject'), isTrue);
    expect(RunGate.requiresReason('requestChanges'), isTrue);
    expect(RunGate.requiresReason('approve'), isFalse);
    expect(runGateKindLabel(stage), 'Stage Gate · Foundation');
    expect(
      RunGate.fromJson(runGateJson(due: false)).isOpen,
      isFalse,
      reason: 'a stage gate without bound evidence is not due',
    );
  });

  test('new run payloads: isolated names a recipe, shared never does', () {
    const isolated = NewRunDraft(
      requestId: 'req-1',
      objective: '  Add OAuth  ',
      workspaceId: 'ws-1',
      coordinatorProfileId: 'codex',
    );
    expect(isolated.toRequest().toJson(), <String, Object?>{
      'requestId': 'req-1',
      'workspaceId': 'ws-1',
      'objective': 'Add OAuth',
      'isolation': 'isolated',
      'coordinatorProfileId': 'codex',
      'recipeSource': <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
      'workerProfileId': 'codex',
      'maxConcurrent': 4,
      'approvalRequired': false,
    });
    const shared = NewRunDraft(
      requestId: 'req-2',
      objective: 'Fix it',
      workspaceId: 'ws-1',
      isolation: RunIsolation.shared,
      recipe: RecipeSource(<String, Object?>{
        'origin': 'builtIn',
        'id': 'feature-delivery',
      }),
      coordinatorProfileId: 'codex',
      workerProfileId: 'claude',
      approvalRequired: true,
    );
    final json = shared.toRequest().toJson();
    expect(json.containsKey('recipeSource'), isFalse);
    expect(json['isolation'], 'shared');
    expect(json['workerProfileId'], 'claude');
    expect(json['approvalRequired'], isTrue);
  });

  test(
    'the New Run form keeps its request id until the form changes',
    () async {
      final client = FakeRunsClient();
      addTearDown(client.dispose);
      final container = _container(client);
      final provider = mobileNewRunFormProvider('host');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final form = container.read(provider.notifier)
        ..setObjective('Add OAuth')
        ..setWorkspace('ws-1')
        ..setCoordinator('codex');
      final first = container.read(provider).requestId;
      client.failures['runs.create'] = RuntimeRequestError('lost');
      await expectLater(form.submit(), throwsA(isA<RuntimeRequestError>()));
      final result = await form.submit();
      expect(result?.runId, 'run-new');
      final sent = client.callsOf('runs.create').toList();
      expect(sent.map((call) => call.payload['requestId']), <Object?>[
        first,
        first,
      ]);
      form.setObjective('Add OAuth login');
      expect(container.read(provider).requestId, isNot(first));
    },
  );

  test('board pages group by bucket and reload on runsChanged only', () async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    final container = _container(client);
    final provider = mobileRunBoardProvider(
      'host',
      bucket: RunBucket.attention,
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final page = await container.read(provider.future);
    expect(page.items.map((run) => run.id), <String>['run-a']);
    expect(page.counts.attention, 1);
    expect(page.counts.history, 1);
    expect(client.callsOf('runs.board').single.payload, <String, Object?>{
      'bucket': 'attention',
      'limit': runBoardPageSize,
    });
    expect(
      await container.read(mobileRunAttentionCountProvider('host').future),
      1,
    );
    client.emit('inboxChanged');
    await Future<void>.delayed(Duration.zero);
    expect(client.callsOf('runs.board'), hasLength(1));
    client.emit(runsChangedEvent, <String, Object?>{'revision': 2});
    await Future<void>.delayed(Duration.zero);
    await container.read(provider.future);
    expect(client.callsOf('runs.board'), hasLength(2));
  });

  test('timeline pages append with the opaque cursor', () async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    final container = _container(client);
    final provider = mobileRunTimelineProvider('host', 'run-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final first = await container.read(provider.future);
    expect(first.items.map((entry) => entry.id), <String>['e0', 'e1']);
    expect(first.nextCursor, 'at:2');
    await container.read(provider.notifier).loadMore();
    final merged = container.read(provider).value!;
    expect(merged.items.map((entry) => entry.id), <String>['e0', 'e1', 'e2']);
    expect(merged.nextCursor, isNull);
    expect(client.callsOf('runs.timeline').last.payload, <String, Object?>{
      'runId': 'run-1',
      'cursor': 'at:2',
      'limit': runTimelinePageSize,
    });
  });

  test('gate decisions carry the request id and the evidence digest', () async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    final container = _container(client);
    final provider = mobileRunActionsProvider('host', 'run-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final actions = container.read(provider.notifier);
    final stage = RunGate.fromJson(runGateJson());
    await expectLater(
      actions.resolveGate(stage, 'reject'),
      throwsA(isA<StateError>()),
    );
    expect(client.callsOf('runs.resolveGate'), isEmpty);
    await actions.resolveGate(stage, 'reject', reason: 'Tests are missing');
    final sent = client.callsOf('runs.resolveGate').single.payload;
    expect(sent['gateId'], 'gate-1');
    expect(sent['decision'], 'reject');
    expect(sent['reason'], 'Tests are missing');
    expect(sent['expectedEvidenceDigest'], 'sha256:evidence');
    expect(sent['requestId'], isA<String>());

    final stall = RunGate.fromJson(
      runGateJson(id: 'gate-s', kind: 'stall', evidenceDigest: null),
    );
    await actions.resolveGate(stall, 'killAndFailover');
    expect(client.callsOf('runs.resolveGate').last.payload, <String, Object?>{
      'requestId': client.callsOf('runs.resolveGate').last.payload['requestId'],
      'gateId': 'gate-s',
      'decision': 'killAndFailover',
    });
  });

  test('a stale gate is marked and cleared on refresh', () async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    final container = _container(client);
    final provider = mobileRunActionsProvider('host', 'run-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    client.failures['runs.resolveGate'] = RuntimeRequestError(
      'stale',
      code: 'gate_stale',
    );
    await expectLater(
      container
          .read(provider.notifier)
          .resolveGate(RunGate.fromJson(runGateJson()), 'approve'),
      throwsA(isA<RuntimeRequestError>()),
    );
    expect(container.read(provider).staleGateIds, <String>{'gate-1'});
    expect(container.read(provider).busy, isEmpty);
    container.read(provider.notifier).clearStale('gate-1');
    expect(container.read(provider).staleGateIds, isEmpty);
  });

  test('control sends the expected sequence; replan needs a reason', () async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    final container = _container(client);
    final provider = mobileRunActionsProvider('host', 'run-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final actions = container.read(provider.notifier);
    await actions.control(RunControlAction.pause, expectedSequence: 3);
    final sent = client.callsOf('runs.control').single.payload;
    expect(sent['expectedSequence'], 3);
    expect(sent['action'], 'pause');
    expect(sent['runId'], 'run-1');
    await expectLater(
      actions.control(RunControlAction.replan, expectedSequence: 3),
      throwsA(isA<StateError>()),
    );
    expect(client.callsOf('runs.control'), hasLength(1));
  });

  test(
    'cleanup applies only a confirmed preview, with confirm: true',
    () async {
      final client = FakeRunsClient();
      addTearDown(client.dispose);
      final container = _container(client);
      final provider = mobileRunCleanupProvider('host', 'run-1');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final cleanup = container.read(provider.notifier)
        ..toggle('attempt-1', selected: true)
        ..setRemoveBranch('attempt-1', remove: true);
      await cleanup.preview();
      final preview = container.read(provider).preview!;
      expect(
        client.callsOf('runs.previewCleanup').single.payload['resources'],
        <Object?>[
          <String, Object?>{'workspaceId': 'attempt-1', 'removeBranch': true},
        ],
      );
      expect(preview.items.single.dirty, isTrue);
      await cleanup.apply(confirmed: false);
      expect(client.callsOf('runs.applyCleanup'), isEmpty);
      await cleanup.apply(confirmed: true);
      expect(
        client.callsOf('runs.applyCleanup').single.payload,
        <String, Object?>{
          'id': preview.id,
          'digest': 'sha256:preview',
          'confirm': true,
        },
      );
      expect(container.read(provider).status?.retiredWorkspaceIds, <String>[
        'attempt-1',
      ]);
    },
  );

  test('push intents route run gates to the run, never a terminal', () {
    final gate = PushNavigationIntent.fromData(<String, Object?>{
      'runtimeId': 'runtime-1',
      'kind': 'decisionGate',
      'category': 'attention',
      'gateId': 'gate-1',
      'gateKind': 'plan',
      'runId': 'run-1',
      'workspaceId': 'ws-1',
      'tabId': 'tab-1',
    });
    expect(gate.eventKind, PushEventKind.runGate);
    expect(gate.gateId, 'gate-1');
    expect(gate.opensRun, isTrue);
    expect(gate.shouldOpenTerminal, isFalse);
    expect(activitySectionForPush(gate), ActivitySection.runs);
    expect(gate.toJson()['gateId'], 'gate-1');
    for (final kind in <String>[
      'gate',
      'orchestration.gate.created',
      'planApproval',
    ]) {
      expect(PushEventKind.parse(kind), PushEventKind.runGate, reason: kind);
    }
    final runless = PushNavigationIntent.fromData(<String, Object?>{
      'runtimeId': 'runtime-1',
      'kind': 'decisionGate',
      'gateId': 'gate-2',
      'workspaceId': 'ws-1',
      'tabId': 'tab-1',
    });
    expect(runless.opensRun, isFalse);
    expect(runless.shouldOpenTerminal, isTrue);
    expect(activitySectionForPush(runless), isNull);
    expect(
      activitySectionForPush(
        PushNavigationIntent.fromData(<String, Object?>{
          'runtimeId': 'runtime-1',
          'kind': 'inboxReply',
          'threadId': 'msg_1',
        }),
      ),
      ActivitySection.questions,
    );
    expect(
      activitySectionForPush(
        PushNavigationIntent.fromData(<String, Object?>{
          'runtimeId': 'runtime-1',
          'kind': 'automation',
          'automationId': 'nightly',
        }),
      ),
      ActivitySection.automations,
    );
  });
}
