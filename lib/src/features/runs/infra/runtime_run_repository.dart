import 'dart:convert';

import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/runs/infra/run_cleanup_requests.dart';
import 'package:alera/src/features/runs/infra/run_repository.dart';
import 'package:alera/src/features/runs/infra/run_watch.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

/// `runs.*` over the runtime host. Every call first checks `runsV1`, so an
/// older host fails closed with [RunsUpdateRequired] instead of a legacy call.
class RuntimeRunRepository with RunCleanupRequests implements RunRepository {
  RuntimeRunRepository(this._client, this._coalescer);

  final RuntimeHostClient _client;
  final RuntimeChangeCoalescer _coalescer;

  static const _mutationTimeout = Duration(seconds: 30);

  @override
  Future<bool> supported() async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          aleraRuntimeHostRunsCapability,
        );
  }

  @override
  Future<Map<String, Object?>> request(
    String verb,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    if (!await supported()) throw const RunsUpdateRequired();
    final response = await _client.runtimeRequest(
      verb,
      payload,
      timeout ?? runtimeSnapshotRequestTimeout,
    );
    return runJsonObject(response);
  }

  Stream<T> _watch<T>(
    String key,
    Future<T> Function() read, {
    Set<String> events = runRefreshEvents,
  }) => watchRuns(
    client: _client,
    coalescer: _coalescer,
    key: key,
    read: read,
    events: events,
  );

  @override
  Future<RunBoardPage> readBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) async =>
      RunBoardPage.fromJson(await request('runs.board', query.toJson()));

  @override
  Stream<RunBoardPage> watchBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) => _watch(
    'runs-board:${jsonEncode(query.toJson())}',
    () => readBoard(query),
  );

  @override
  Future<RunSnapshot> readRun(
    String runId, {
    String? afterTaskId,
    int? revision,
    int limit = 100,
  }) async => RunSnapshot.fromJson(
    await request('runs.snapshot', <String, Object?>{
      'runId': runId,
      'afterTaskId': ?afterTaskId,
      'revision': ?revision,
      'limit': limit,
    }),
  );

  @override
  Stream<RunSnapshot> watchRun(String runId) =>
      _watch('runs-snapshot:$runId', () => readRun(runId));

  @override
  Future<TaskInspection> readTask(
    String runId,
    String taskId, {
    TaskHistoryCursor? cursor,
    int limit = 20,
  }) async => TaskInspection.fromJson(
    await request('runs.task', <String, Object?>{
      'runId': runId,
      'taskId': taskId,
      'cursor': ?cursor?.toMap(),
      'limit': limit,
    }),
  );

  @override
  Stream<TaskInspection> watchTask(String runId, String taskId) =>
      _watch('runs-task:$runId:$taskId', () => readTask(runId, taskId));

  @override
  Future<RunTimelinePage> readTimeline(
    String runId, {
    String? cursor,
    int limit = 50,
    List<String> kinds = const <String>[],
    String? taskId,
  }) async => RunTimelinePage.fromJson(
    await request('runs.timeline', <String, Object?>{
      'runId': runId,
      'cursor': ?cursor,
      'limit': limit,
      if (kinds.isNotEmpty) 'kinds': kinds,
      'taskId': ?taskId,
    }),
  );

  @override
  Stream<RunTimelinePage> watchTimeline(
    String runId, {
    int limit = 50,
    List<String> kinds = const <String>[],
  }) => _watch(
    'runs-timeline:$runId:$limit:${kinds.join(',')}',
    () => readTimeline(runId, limit: limit, kinds: kinds),
    // Messages between run agents do not bump the board revision.
    events: <String>{...runRefreshEvents, runConversationsChangedEvent},
  );

  @override
  Future<RunSource> source(String workspaceId) async => RunSource.fromJson(
    await request('runs.source', <String, Object?>{'workspaceId': workspaceId}),
  );

  @override
  Future<RunPlanView?> plan(String runId, {int? revision}) async {
    final response = await request('runs.plan', <String, Object?>{
      'runId': runId,
      'revision': ?revision,
    });
    final plan = response['plan'];
    return plan == null ? null : RunPlanView.fromJson(runJsonObject(plan));
  }

  @override
  Future<List<RunGate>> gates(
    String runId, {
    String? taskId,
    RunGateKind? kind,
    RunGateStatus? status,
  }) async {
    final response = await request('runs.gates', <String, Object?>{
      'runId': runId,
      'taskId': ?taskId,
      'kind': ?kind?.name,
      'status': ?status?.name,
    });
    return <RunGate>[
      for (final item in response['items'] as List? ?? const <Object?>[])
        RunGate.fromJson(runJsonObject(item)),
    ];
  }

  @override
  Future<RunGateDetail> gate(String gateId) async => RunGateDetail.fromJson(
    await request('runs.gate', <String, Object?>{'gateId': gateId}),
  );

  @override
  Stream<RunGateDetail> watchGate(String gateId) =>
      _watch('runs-gate:$gateId', () => gate(gateId));

  @override
  Future<RunCreateResult> create(RunCreateRequest create) async =>
      RunCreateResult.fromJson(
        await request(
          'runs.create',
          create.toPayload(),
          timeout: const Duration(seconds: 60),
        ),
      );

  @override
  Future<RunGateReceipt> resolveGate({
    required String requestId,
    required String gateId,
    required String decision,
    String? reason,
    List<String>? taskIds,
    String? expectedEvidenceDigest,
  }) async => RunGateReceipt.fromJson(
    await request('runs.resolveGate', <String, Object?>{
      'requestId': requestId,
      'gateId': gateId,
      'decision': decision,
      'reason': ?reason,
      'taskIds': ?taskIds,
      'expectedEvidenceDigest': ?expectedEvidenceDigest,
    }, timeout: _mutationTimeout),
  );

  @override
  Future<RunControlReceipt> control({
    required String requestId,
    required String runId,
    required int expectedSequence,
    required RunControlAction action,
    String? reason,
    List<String>? taskIds,
  }) async => RunControlReceipt.fromJson(
    await request('runs.control', <String, Object?>{
      'requestId': requestId,
      'runId': runId,
      'expectedSequence': expectedSequence,
      'action': action.name,
      'reason': ?reason,
      'taskIds': ?taskIds,
    }, timeout: _mutationTimeout),
  );

  @override
  Future<Map<String, Object?>> retryTask({
    required String requestId,
    required String runId,
    required String taskId,
  }) => request('runs.retryTask', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'taskId': taskId,
  }, timeout: _mutationTimeout);

  @override
  Future<Map<String, Object?>> retryIntegration({
    required String requestId,
    required String runId,
    required String taskId,
  }) => request('runs.retryIntegration', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'taskId': taskId,
  }, timeout: _mutationTimeout);

  @override
  Future<RunControlReceipt> retryCancellation({
    required String requestId,
    required String runId,
    required int expectedSequence,
  }) async => RunControlReceipt.fromJson(
    await request('runs.retryCancellation', <String, Object?>{
      'requestId': requestId,
      'runId': runId,
      'expectedSequence': expectedSequence,
    }, timeout: _mutationTimeout),
  );
}
