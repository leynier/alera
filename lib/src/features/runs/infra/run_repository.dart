import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';

/// Everything Activity reads from and asks of runs. Reads have a `watch`
/// twin that re-reads on `runsChanged`; mutations carry a client request id so
/// a retried request replays the stored receipt instead of acting twice.
abstract interface class RunRepository {
  /// Whether the host advertises `runsV1`.
  Future<bool> supported();

  Future<RunBoardPage> readBoard([RunBoardQuery query]);
  Stream<RunBoardPage> watchBoard([RunBoardQuery query]);

  Future<RunSnapshot> readRun(
    String runId, {
    String? afterTaskId,
    int? revision,
    int limit,
  });
  Stream<RunSnapshot> watchRun(String runId);

  Future<TaskInspection> readTask(
    String runId,
    String taskId, {
    TaskHistoryCursor? cursor,
    int limit,
  });
  Stream<TaskInspection> watchTask(String runId, String taskId);

  Future<RunTimelinePage> readTimeline(
    String runId, {
    String? cursor,
    int limit,
    List<String> kinds,
    String? taskId,
  });
  Stream<RunTimelinePage> watchTimeline(
    String runId, {
    int limit,
    List<String> kinds,
  });

  Future<RunSource> source(String workspaceId);
  Future<RunPlanView?> plan(String runId, {int? revision});
  Future<List<RunGate>> gates(
    String runId, {
    String? taskId,
    RunGateKind? kind,
    RunGateStatus? status,
  });
  Future<RunGateDetail> gate(String gateId);
  Stream<RunGateDetail> watchGate(String gateId);

  Future<RunCreateResult> create(RunCreateRequest create);
  Future<RunGateReceipt> resolveGate({
    required String requestId,
    required String gateId,
    required String decision,
    String? reason,
    List<String>? taskIds,
    String? expectedEvidenceDigest,
  });
  Future<RunControlReceipt> control({
    required String requestId,
    required String runId,
    required int expectedSequence,
    required RunControlAction action,
    String? reason,
    List<String>? taskIds,
  });
  Future<Map<String, Object?>> retryTask({
    required String requestId,
    required String runId,
    required String taskId,
  });
  Future<Map<String, Object?>> retryIntegration({
    required String requestId,
    required String runId,
    required String taskId,
  });
  Future<RunControlReceipt> retryCancellation({
    required String requestId,
    required String runId,
    required int expectedSequence,
  });

  Future<RunCleanupPage<RunCleanupResource>> resources(
    String runId, {
    int? beforeRow,
  });
  Future<RunCleanupPage<RunCleanupHistoryItem>> cleanups(
    String runId, {
    int? beforeRow,
  });
  Future<RunCleanupPreview> previewCleanup(
    String id,
    String runId,
    Map<String, bool> resources,
  );
  Future<RunCleanupStatus> cleanupStatus(String id, String runId);
  Future<RunCleanupStatus> applyCleanup(
    RunCleanupPreview preview, {
    bool retry,
  });
  Future<RunCleanupStatus> abandonCleanup(RunCleanupPreview preview);
}
