import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'run_gate.mapper.dart';

@MappableEnum(defaultValue: RunGateKind.decision)
enum RunGateKind { decision, stall, plan, stage }

@MappableEnum(defaultValue: RunGateStatus.invalidated)
enum RunGateStatus { pending, resolved, timeout, invalidated }

/// Option ids the runtime accepts for each fixed-option gate kind.
abstract final class RunGateOptions {
  static const approve = 'approve';
  static const requestChanges = 'requestChanges';
  static const reject = 'reject';
  static const killAndFailover = 'killAndFailover';
  static const keepWaiting = 'keepWaiting';
  static const abortStage = 'abortStage';

  static const review = <String>[approve, requestChanges, reject];
  static const stall = <String>[killAndFailover, keepWaiting, abortStage];
}

/// A gate as `runs.gates`, `runs.gate` and `runs.snapshot` report it.
@MappableClass()
class RunGate with RunGateMappable {
  const RunGate({
    required this.id,
    this.runId,
    this.taskId,
    required this.kind,
    this.scope = '',
    this.question = '',
    this.options = const <String>[],
    required this.status,
    this.due = false,
    this.resolution,
    this.reason,
    this.planRevision,
    this.evidenceDigest,
    this.integrationSha,
    this.actorKind,
    this.actorId,
    required this.createdAt,
    this.resolvedAt,
  });

  static RunGate fromJson(Map<String, Object?> json) =>
      RunGateMapper.fromMap(json);

  final String id;
  final String? runId;
  final String? taskId;
  final RunGateKind kind;
  final String scope;
  final String question;
  final List<String> options;
  final RunGateStatus status;
  final bool due;
  final String? resolution;
  final String? reason;
  final int? planRevision;
  final String? evidenceDigest;
  final String? integrationSha;
  final String? actorKind;
  final String? actorId;
  final String createdAt;
  final String? resolvedAt;

  bool get pending => status == RunGateStatus.pending;

  /// Whether a person can decide it now (stage gates wait for evidence).
  bool get actionable => pending && due;
}

/// A stage gate's evidence row: one task of the stage or a prerequisite.
@MappableClass()
class RunGateEvidenceTask with RunGateEvidenceTaskMappable {
  const RunGateEvidenceTask({
    required this.taskId,
    this.logicalId,
    required this.title,
    this.stageId,
    required this.status,
    this.resultPreview,
    this.resultTruncated = false,
    this.resultDigest,
    this.artifactDigest,
    this.integrationSha,
    this.integrationState,
    this.conflictPaths = const <String>[],
    this.assignee,
  });

  final String taskId;
  final String? logicalId;
  final String title;
  final String? stageId;
  final String status;
  final String? resultPreview;
  final bool resultTruncated;
  final String? resultDigest;
  final String? artifactDigest;
  final String? integrationSha;
  final String? integrationState;
  final List<String> conflictPaths;
  final String? assignee;
}

/// `runs.gate`: the gate, its plan (plan gates) and its evidence.
@MappableClass()
class RunGateDetail with RunGateDetailMappable {
  const RunGateDetail({
    required this.gate,
    this.plan,
    this.tasks = const <RunGateEvidenceTask>[],
  });

  static RunGateDetail fromJson(Map<String, Object?> json) =>
      RunGateDetailMapper.fromMap(json);

  final RunGate gate;
  final RunPlanView? plan;
  final List<RunGateEvidenceTask> tasks;
}

/// `runs.resolveGate` response.
@MappableClass()
class RunGateReceipt with RunGateReceiptMappable {
  const RunGateReceipt({
    required this.requestId,
    required this.gate,
    this.runId,
    this.runStatus,
    this.planRevision,
    this.changesRequested = false,
    this.coordinatorAction = 'none',
  });

  static RunGateReceipt fromJson(Map<String, Object?> json) =>
      RunGateReceiptMapper.fromMap(json);

  final String requestId;
  final RunGate gate;
  final String? runId;
  final String? runStatus;
  final int? planRevision;
  final bool changesRequested;
  final String coordinatorAction;
}
