import 'dart:async';

import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/runs/infra/run_repository.dart';

import 'run_cleanup_catalog_fixture.dart';
import 'run_cleanup_fixture.dart';
import 'runs_fixtures.dart';

/// An in-memory [RunRepository]. Watches re-read on [changed]; every request
/// is recorded in [calls] as `(verb, payload)`.
class FakeRunRepository implements RunRepository {
  FakeRunRepository() {
    snapshots['run-1'] = runSnapshot();
  }

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  /// Thrown by every read, such as `RunsUpdateRequired`.
  Object? error;

  /// Thrown by the next mutation, then cleared.
  Object? mutationError;

  RunBoardPage board = runsBoardPage();
  final Map<String, RunSnapshot> snapshots = <String, RunSnapshot>{};
  final Map<String, TaskInspection> tasks = <String, TaskInspection>{
    'task-2': taskInspection(),
  };
  RunGateDetail? gateDetail;

  /// Replaces the first timeline page when set.
  RunTimelinePage? timeline;
  RunPlanView? planView;
  String cleanupState = 'preview';
  List<Object?> cleanupResourceItems =
      cleanupResourcesFixture()['items']! as List<Object?>;

  /// The second resource page, when a test needs more than one.
  List<Object?> moreCleanupResourceItems = const <Object?>[];

  void changed() => _changes.add(null);

  Future<void> dispose() => _changes.close();

  T _read<T>(T Function() value) {
    final failure = error;
    if (failure != null) throw failure;
    return value();
  }

  Stream<T> _watch<T>(Future<T> Function() read) =>
      Stream<T>.multi((controller) {
        Future<void> emit() async {
          try {
            controller.add(await read());
          } on Object catch (error, stack) {
            controller.addError(error, stack);
          }
        }

        unawaited(emit());
        final subscription = _changes.stream.listen((_) => unawaited(emit()));
        controller.onCancel = subscription.cancel;
      });

  Future<T> _mutate<T>(
    String verb,
    Map<String, Object?> payload,
    T Function() result,
  ) async {
    calls.add((verb, payload));
    final failure = mutationError;
    if (failure != null) {
      mutationError = null;
      throw failure;
    }
    return result();
  }

  @override
  Future<bool> supported() async => error == null;

  @override
  Future<RunBoardPage> readBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) async {
    calls.add(('runs.board', query.toJson()));
    return _read(() {
      final bucket = query.bucket;
      if (bucket == null) return board;
      return board.copyWith(
        items: board.items.where((run) => run.bucket == bucket).toList(),
      );
    });
  }

  @override
  Stream<RunBoardPage> watchBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) => _watch(() => readBoard(query));

  @override
  Future<RunSnapshot> readRun(
    String runId, {
    String? afterTaskId,
    int? revision,
    int limit = 100,
  }) async =>
      _read(() => snapshots[runId] ?? runSnapshot(run: runSummary(id: runId)));

  @override
  Stream<RunSnapshot> watchRun(String runId) => _watch(() => readRun(runId));

  @override
  Future<TaskInspection> readTask(
    String runId,
    String taskId, {
    TaskHistoryCursor? cursor,
    int limit = 20,
  }) async => _read(() => tasks[taskId] ?? taskInspection(taskId: taskId));

  @override
  Stream<TaskInspection> watchTask(String runId, String taskId) =>
      _watch(() => readTask(runId, taskId));

  @override
  Future<RunTimelinePage> readTimeline(
    String runId, {
    String? cursor,
    int limit = 50,
    List<String> kinds = const <String>[],
    String? taskId,
  }) async {
    calls.add((
      'runs.timeline',
      <String, Object?>{'runId': runId, 'cursor': ?cursor, 'kinds': kinds},
    ));
    return _read(() {
      final page = cursor == null
          ? timeline ?? runTimelinePage()
          : runTimelinePage(cursor: cursor);
      if (kinds.isEmpty) return page;
      return page.copyWith(
        items: page.items.where((entry) => kinds.contains(entry.kind)).toList(),
      );
    });
  }

  @override
  Stream<RunTimelinePage> watchTimeline(
    String runId, {
    int limit = 50,
    List<String> kinds = const <String>[],
  }) => _watch(() => readTimeline(runId, limit: limit, kinds: kinds));

  @override
  Future<RunSource> source(String workspaceId) async =>
      _read(() => const RunSource(sha: 'a1b2c3d4e5f6'));

  @override
  Future<RunPlanView?> plan(String runId, {int? revision}) async =>
      _read(() => planView);

  @override
  Future<List<RunGate>> gates(
    String runId, {
    String? taskId,
    RunGateKind? kind,
    RunGateStatus? status,
  }) async {
    calls.add(('runs.gates', <String, Object?>{'runId': runId}));
    return _read(() => snapshots[runId]?.pendingGates ?? const <RunGate>[]);
  }

  @override
  Future<RunGateDetail> gate(String gateId) async =>
      _read(() => gateDetail ?? RunGateDetail(gate: runGate(id: gateId)));

  @override
  Stream<RunGateDetail> watchGate(String gateId) => _watch(() => gate(gateId));

  @override
  Future<RunCreateResult> create(RunCreateRequest create) => _mutate(
    'runs.create',
    create.toPayload(),
    () => RunCreateResult(
      run: RunCreated(
        runId: 'run-new',
        status: 'planning',
        isolation: create.isolation,
      ),
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
  }) => _mutate(
    'runs.resolveGate',
    <String, Object?>{
      'requestId': requestId,
      'gateId': gateId,
      'decision': decision,
      'reason': ?reason,
      'taskIds': ?taskIds,
      'expectedEvidenceDigest': ?expectedEvidenceDigest,
    },
    () => RunGateReceipt(
      requestId: requestId,
      gate: runGate(id: gateId),
    ),
  );

  @override
  Future<RunControlReceipt> control({
    required String requestId,
    required String runId,
    required int expectedSequence,
    required RunControlAction action,
    String? reason,
    List<String>? taskIds,
  }) => _mutate(
    'runs.control',
    <String, Object?>{
      'requestId': requestId,
      'runId': runId,
      'expectedSequence': expectedSequence,
      'action': action.name,
      'reason': ?reason,
    },
    () => RunControlReceipt(
      requestId: requestId,
      runId: runId,
      action: action.name,
      sequence: expectedSequence + 1,
    ),
  );

  @override
  Future<Map<String, Object?>> retryTask({
    required String requestId,
    required String runId,
    required String taskId,
  }) => _mutate('runs.retryTask', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'taskId': taskId,
  }, () => <String, Object?>{});

  @override
  Future<Map<String, Object?>> retryIntegration({
    required String requestId,
    required String runId,
    required String taskId,
  }) => _mutate('runs.retryIntegration', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'taskId': taskId,
  }, () => <String, Object?>{});

  @override
  Future<RunControlReceipt> retryCancellation({
    required String requestId,
    required String runId,
    required int expectedSequence,
  }) => _mutate(
    'runs.retryCancellation',
    <String, Object?>{
      'requestId': requestId,
      'runId': runId,
      'expectedSequence': expectedSequence,
    },
    () => RunControlReceipt(
      requestId: requestId,
      runId: runId,
      action: 'retryCancellation',
    ),
  );

  @override
  Future<RunCleanupPage<RunCleanupResource>> resources(
    String runId, {
    int? beforeRow,
  }) async => _read(
    () => RunCleanupPage<RunCleanupResource>.fromJson(<String, Object?>{
      'runId': 'run',
      'revision': 4,
      'nextBeforeRow': beforeRow == null && moreCleanupResourceItems.isNotEmpty
          ? 10
          : null,
      'items': beforeRow == null
          ? cleanupResourceItems
          : moreCleanupResourceItems,
    }, RunCleanupResource.fromJson),
  );

  @override
  Future<RunCleanupPage<RunCleanupHistoryItem>> cleanups(
    String runId, {
    int? beforeRow,
  }) async => _read(
    () => RunCleanupPage.fromJson(
      cleanupHistoryFixture(),
      RunCleanupHistoryItem.fromJson,
    ),
  );

  @override
  Future<RunCleanupPreview> previewCleanup(
    String id,
    String runId,
    Map<String, bool> resources,
  ) => _mutate('runs.previewCleanup', <String, Object?>{
    'id': id,
    'runId': runId,
    'resources': resources,
  }, () => RunCleanupPreview.fromJson(cleanupPreviewFixture()));

  @override
  Future<RunCleanupStatus> cleanupStatus(String id, String runId) async =>
      _read(
        () => RunCleanupStatus.fromJson(cleanupStatusFixture(cleanupState)),
      );

  @override
  Future<RunCleanupStatus> applyCleanup(
    RunCleanupPreview preview, {
    bool retry = false,
  }) => _mutate(
    retry ? 'runs.retryCleanup' : 'runs.applyCleanup',
    <String, Object?>{'id': preview.id, 'digest': preview.digest},
    () {
      cleanupState = 'retired';
      return RunCleanupStatus.fromJson(cleanupStatusFixture('retired'));
    },
  );

  @override
  Future<RunCleanupStatus> abandonCleanup(RunCleanupPreview preview) => _mutate(
    'runs.abandonCleanup',
    <String, Object?>{'id': preview.id, 'digest': preview.digest},
    () {
      cleanupState = 'abandoned';
      return RunCleanupStatus.fromJson(cleanupStatusFixture('abandoned'));
    },
  );
}
