import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'run_task_inspection.mapper.dart';

@MappableClass()
class TaskHistoryCursor with TaskHistoryCursorMappable {
  const TaskHistoryCursor({
    required this.occurredAt,
    required this.id,
    required this.revision,
  });

  final String occurredAt;
  final String id;
  final int revision;
}

@MappableClass()
class TaskHistoryEntry with TaskHistoryEntryMappable {
  const TaskHistoryEntry({
    required this.id,
    required this.occurredAt,
    required this.kind,
    required this.status,
    this.summary,
  });

  final String id;
  final String occurredAt;

  /// `attempt` or `event`.
  final String kind;
  final String status;
  final String? summary;
}

@MappableClass()
class TaskResultInspection with TaskResultInspectionMappable {
  const TaskResultInspection({
    this.summary,
    this.completionKind,
    this.artifacts = const <String>[],
    this.validation = const <String>[],
    this.preview,
    this.truncated = false,
  });

  final String? summary;
  final String? completionKind;
  final List<String> artifacts;
  final List<String> validation;
  final String? preview;
  final bool truncated;
}

/// The latest isolated attempt of a task, with its integration.
@MappableClass()
class TaskAttemptInspection with TaskAttemptInspectionMappable {
  const TaskAttemptInspection({
    this.planRevision = 0,
    this.attempt = 1,
    this.phase = '',
    this.canRetry = false,
    this.canRetryIntegration = false,
    this.state = '',
    this.integrationId,
    this.integrationRequestId,
    this.launchId,
    required this.executionWorkspaceId,
    this.worktree,
    this.branch,
    this.baseSha,
    this.completionSha,
    this.integratedSha,
    this.conflictPaths = const <String>[],
    this.conflictsTruncated = false,
    this.error,
  });

  final int planRevision;
  final int attempt;
  final String phase;
  final bool canRetry;
  final bool canRetryIntegration;
  final String state;
  final String? integrationId;
  final String? integrationRequestId;
  final String? launchId;
  final String executionWorkspaceId;
  final String? worktree;
  final String? branch;
  final String? baseSha;
  final String? completionSha;
  final String? integratedSha;
  final List<String> conflictPaths;
  final bool conflictsTruncated;
  final String? error;
}

/// `runs.task`: one task with its result, attempt, gates and history.
@MappableClass()
class TaskInspection with TaskInspectionMappable {
  const TaskInspection({
    required this.revision,
    required this.taskId,
    required this.runId,
    required this.title,
    this.description = '',
    this.descriptionTruncated = false,
    required this.status,
    this.stageId,
    required this.workspaceId,
    this.workspaceName,
    this.workspacePath,
    this.branch,
    this.baseSha,
    this.profile,
    this.terminalHandle,
    this.dependencies = const <String>[],
    this.dependenciesTruncated = false,
    this.result = const TaskResultInspection(),
    this.history = const <TaskHistoryEntry>[],
    this.nextCursor,
    this.attempt,
    this.gates = const <RunGate>[],
    this.logicalId,
    this.planRevision,
    this.roleId,
  });

  static TaskInspection fromJson(Map<String, Object?> json) =>
      TaskInspectionMapper.fromMap(json);

  final int revision;
  final String taskId;
  final String runId;
  final String title;
  final String description;
  final bool descriptionTruncated;
  final String status;
  final String? stageId;
  final String workspaceId;
  final String? workspaceName;
  final String? workspacePath;
  final String? branch;
  final String? baseSha;
  final String? profile;
  final String? terminalHandle;
  final List<String> dependencies;
  final bool dependenciesTruncated;
  final TaskResultInspection result;
  final List<TaskHistoryEntry> history;
  final TaskHistoryCursor? nextCursor;
  final TaskAttemptInspection? attempt;
  final List<RunGate> gates;
  final String? logicalId;
  final int? planRevision;
  final String? roleId;

  /// Where the work happened: the attempt worktree for isolated runs.
  String get executionWorkspaceId =>
      attempt?.executionWorkspaceId ?? workspaceId;
}
