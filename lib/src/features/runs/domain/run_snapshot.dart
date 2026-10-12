import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'run_snapshot.mapper.dart';

/// The latest isolated attempt of a task.
@MappableClass()
class RunTaskAttempt with RunTaskAttemptMappable {
  const RunTaskAttempt({
    required this.workspaceId,
    this.attempt = 1,
    this.branch,
    this.baseSha,
    this.phase = '',
  });

  final String workspaceId;
  final int attempt;
  final String? branch;
  final String? baseSha;
  final String phase;
}

@MappableClass()
class RunTaskIntegration with RunTaskIntegrationMappable {
  const RunTaskIntegration({required this.state, this.sha});

  final String state;
  final String? sha;
}

/// A task row of `runs.snapshot`.
@MappableClass()
class RunTask with RunTaskMappable {
  const RunTask({
    required this.id,
    this.logicalId,
    required this.title,
    required this.status,
    this.stageId,
    this.roleId,
    this.planRevision,
    required this.workspaceId,
    this.dependencies = const <String>[],
    this.dependenciesTruncated = false,
    this.attemptState,
    this.attempt,
    this.integration,
    this.profile,
    this.assignee,
    this.startedAt,
    this.completedAt,
    this.updatedAt,
  });

  final String id;
  final String? logicalId;
  final String title;
  final String status;
  final String? stageId;
  final String? roleId;
  final int? planRevision;
  final String workspaceId;
  final List<String> dependencies;
  final bool dependenciesTruncated;

  /// Isolated attempt progress; absent for shared runs.
  final String? attemptState;
  final RunTaskAttempt? attempt;
  final RunTaskIntegration? integration;
  final String? profile;
  final String? assignee;
  final String? startedAt;
  final String? completedAt;

  /// Absent from older hosts.
  final String? updatedAt;
}

@MappableClass()
class RunPlanSummary with RunPlanSummaryMappable {
  const RunPlanSummary({
    required this.revision,
    this.digest = '',
    this.previousRevision,
    this.changeReason,
    this.state = 'approved',
  });

  final int revision;
  final String digest;
  final int? previousRevision;
  final String? changeReason;

  /// `planning`, `awaitingApproval`, `approved` or `superseded`.
  final String state;
}

@MappableClass()
class RunCoordinatorSummary with RunCoordinatorSummaryMappable {
  const RunCoordinatorSummary({
    this.handle,
    this.tabId,
    this.profileId,
    this.state = 'none',
    this.error,
  });

  final String? handle;
  final String? tabId;
  final String? profileId;

  /// `none`, `reserved`, `started` or `attention`.
  final String state;
  final String? error;
}

@MappableClass()
class RunIntegrationSummary with RunIntegrationSummaryMappable {
  const RunIntegrationSummary({this.workspaceId, this.branch, this.sha});

  final String? workspaceId;
  final String? branch;
  final String? sha;
}

@MappableClass()
class RunCleanupSummary with RunCleanupSummaryMappable {
  const RunCleanupSummary({
    required this.id,
    required this.state,
    this.error,
    this.abandoned = false,
  });

  final String id;
  final String state;
  final String? error;
  final bool abandoned;
}

/// `runs.snapshot`: one run with its plan, coordinator, gates and tasks.
@MappableClass()
class RunSnapshot with RunSnapshotMappable {
  const RunSnapshot({
    required this.revision,
    required this.run,
    this.objective = '',
    this.objectiveTruncated = false,
    this.controlSequence = 0,
    this.stallPolicy = 'ask',
    this.maxConcurrent = 1,
    this.stopReason,
    this.recipeSource,
    this.sourceSha,
    this.plan,
    this.coordinator = const RunCoordinatorSummary(),
    this.integration,
    this.pendingGates = const <RunGate>[],
    this.cleanup,
    this.resourceCount,
    this.tasks = const <RunTask>[],
    this.nextTaskId,
  });

  static RunSnapshot fromJson(Map<String, Object?> json) =>
      RunSnapshotMapper.fromMap(json);

  final int revision;
  final RunSummary run;
  final String objective;
  final bool objectiveTruncated;
  final int controlSequence;
  final String stallPolicy;
  final int maxConcurrent;
  final String? stopReason;
  final Map<String, Object?>? recipeSource;
  final String? sourceSha;
  final RunPlanSummary? plan;
  final RunCoordinatorSummary coordinator;
  final RunIntegrationSummary? integration;
  final List<RunGate> pendingGates;
  final RunCleanupSummary? cleanup;

  /// Worktrees and branches the run still retains; absent from older hosts.
  final int? resourceCount;
  final List<RunTask> tasks;
  final String? nextTaskId;
}
