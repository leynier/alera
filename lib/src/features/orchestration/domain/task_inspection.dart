import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';

class TaskHistoryCursor {
  const TaskHistoryCursor(this.occurredAt, this.id, this.revision);
  factory TaskHistoryCursor.fromJson(Map<String, Object?> json) =>
      TaskHistoryCursor(
        json['occurred_at'] as String,
        json['id'] as String,
        json['revision'] as int,
      );
  final String occurredAt;
  final String id;
  final int revision;
  Map<String, Object?> toJson() => {
    'occurred_at': occurredAt,
    'id': id,
    'revision': revision,
  };
}

class TaskHistoryEntry {
  const TaskHistoryEntry({
    required this.id,
    required this.occurredAt,
    required this.kind,
    required this.status,
    this.summary,
  });
  factory TaskHistoryEntry.fromJson(Map<String, Object?> json) =>
      TaskHistoryEntry(
        id: json['id'] as String,
        occurredAt: json['occurred_at'] as String,
        kind: json['kind'] as String,
        status: json['status'] as String,
        summary: json['summary'] as String?,
      );
  final String id;
  final String occurredAt;
  final String kind;
  final String status;
  final String? summary;
}

class TaskResultInspection {
  const TaskResultInspection({
    this.summary,
    this.completionKind,
    this.artifacts = const [],
    this.validation = const [],
    this.preview,
    this.truncated = false,
  });
  factory TaskResultInspection.fromJson(
    Map<String, Object?> json,
  ) => TaskResultInspection(
    summary: json['summary'] as String?,
    completionKind: json['completion_kind'] as String?,
    artifacts: List.unmodifiable((json['artifacts'] as List).cast<String>()),
    validation: List.unmodifiable((json['validation'] as List).cast<String>()),
    preview: json['preview'] as String?,
    truncated: json['truncated'] as bool,
  );
  final String? summary;
  final String? completionKind;
  final List<String> artifacts;
  final List<String> validation;
  final String? preview;
  final bool truncated;
}

class TaskInspection {
  const TaskInspection({
    required this.revision,
    required this.taskId,
    required this.runId,
    required this.title,
    required this.description,
    required this.status,
    required this.workspaceId,
    required this.result,
    this.descriptionTruncated = false,
    this.stageId,
    this.workspaceName,
    this.workspacePath,
    this.branch,
    this.baseSha,
    this.profile,
    this.terminalHandle,
    this.dependencies = const [],
    this.dependenciesTruncated = false,
    this.history = const [],
    this.nextCursor,
  });

  factory TaskInspection.fromJson(Map<String, Object?> json) => TaskInspection(
    revision: json['revision'] as int,
    taskId: json['task_id'] as String,
    runId: json['run_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    status: json['status'] as String,
    workspaceId: json['workspace_id'] as String,
    descriptionTruncated: json['description_truncated'] as bool,
    stageId: json['stage_id'] as String?,
    workspaceName: json['workspace_name'] as String?,
    workspacePath: json['workspace_path'] as String?,
    branch: json['branch'] as String?,
    baseSha: json['base_sha'] as String?,
    profile: json['profile'] as String?,
    terminalHandle: json['terminal_handle'] as String?,
    dependencies: List.unmodifiable(
      (json['dependencies'] as List).cast<String>(),
    ),
    dependenciesTruncated: json['dependencies_truncated'] as bool,
    result: TaskResultInspection.fromJson(boardJsonObject(json['result'])),
    history: List.unmodifiable([
      for (final entry in json['history'] as List)
        TaskHistoryEntry.fromJson(boardJsonObject(entry)),
    ]),
    nextCursor: json['next_cursor'] == null
        ? null
        : TaskHistoryCursor.fromJson(boardJsonObject(json['next_cursor'])),
  );

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
}
