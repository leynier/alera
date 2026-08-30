import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';

class RunTaskSummary {
  const RunTaskSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.workspaceId,
    this.stageId,
    this.dependencies = const [],
    this.dependenciesTruncated = false,
  });

  factory RunTaskSummary.fromJson(Map<String, Object?> json) => RunTaskSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    workspaceId: json['workspace_id'] as String,
    stageId: json['stage_id'] as String?,
    dependencies: List<String>.unmodifiable(
      (json['dependencies'] as List? ?? const []).cast<String>(),
    ),
    dependenciesTruncated: json['dependencies_truncated'] as bool? ?? false,
  );

  final String id;
  final String title;
  final String status;
  final String workspaceId;
  final String? stageId;
  final List<String> dependencies;
  final bool dependenciesTruncated;
}

class RunSnapshot {
  RunSnapshot({
    required this.revision,
    required this.run,
    required this.objective,
    required this.objectiveTruncated,
    required List<RunTaskSummary> tasks,
    this.nextTaskId,
  }) : tasks = List.unmodifiable(tasks);

  factory RunSnapshot.fromJson(Map<String, Object?> json) => RunSnapshot(
    revision: json['revision'] as int,
    run: RunSummary.fromJson(boardJsonObject(json['run'])),
    objective: json['objective'] as String,
    objectiveTruncated: json['objective_truncated'] as bool,
    tasks: [
      for (final task in json['tasks'] as List)
        RunTaskSummary.fromJson(boardJsonObject(task)),
    ],
    nextTaskId: json['next_task_id'] as String?,
  );

  final int revision;
  final RunSummary run;
  final String objective;
  final bool objectiveTruncated;
  final List<RunTaskSummary> tasks;
  final String? nextTaskId;
}
