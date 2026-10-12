import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';

class const RunPlanStage({
  required final String id,
  required final String title,
  final String? profile,
  final bool gate = false,
  final String? gateKind,
});

class const RunPlanTask({
  required final String id,
  required final String title,
  final String spec = '',
  final String? stageId,
  final String? status,
});

/// A plan revision, as `runs.plan` and plan gates show it.
class const RunPlanView({
  required final int revision,
  final String digest = '',
  final String? changeReason,
  final String? recipeName,
  final List<RunPlanStage> stages = const <RunPlanStage>[],
  final List<RunPlanTask> tasks = const <RunPlanTask>[],
}) {
  static RunPlanView? tryParse(Object? value) {
    final json = asJsonMap(value);
    if (json.isEmpty) return null;
    return RunPlanView(
      revision: runInt(json['revision']),
      digest: json.optionalString('digest') ?? '',
      changeReason: json.optionalString('changeReason'),
      recipeName: asJsonMap(json['recipe']).optionalString('name'),
      stages: <RunPlanStage>[
        for (final item in json.objectList('stages'))
          if (asJsonMap(item).optionalString('id') case final id?)
            RunPlanStage(
              id: id,
              title: asJsonMap(item).optionalString('title') ?? id,
              profile: asJsonMap(item).optionalString('profile'),
              gate: asJsonMap(item)['gate'] == true,
              gateKind: asJsonMap(item).optionalString('gateKind'),
            ),
      ],
      tasks: <RunPlanTask>[
        for (final item in json.objectList('tasks'))
          if (asJsonMap(item).optionalString('id') case final id?)
            RunPlanTask(
              id: id,
              title: asJsonMap(item).optionalString('title') ?? id,
              spec: asJsonMap(item).optionalString('spec') ?? '',
              stageId: asJsonMap(item).optionalString('stageId'),
              status: asJsonMap(item).optionalString('status'),
            ),
      ],
    );
  }
}

/// Evidence a stage, decision or stall gate is judged on.
class const RunGateEvidenceTask({
  required final String taskId,
  required final String title,
  required final String status,
  final String? stageId,
  final String? resultPreview,
  final bool resultTruncated = false,
  final String? integrationSha,
  final String? integrationState,
  final List<String> conflictPaths = const <String>[],
  final String? assignee,
}) {
  factory fromJson(Map<String, Object?> json) => RunGateEvidenceTask(
    taskId: json.requiredString('taskId'),
    title: json.optionalString('title') ?? json.requiredString('taskId'),
    status: json.optionalString('status') ?? '',
    stageId: json.optionalString('stageId'),
    resultPreview: json.optionalString('resultPreview'),
    resultTruncated: json['resultTruncated'] == true,
    integrationSha: json.optionalString('integrationSha'),
    integrationState: json.optionalString('integrationState'),
    conflictPaths: json.stringList('conflictPaths'),
    assignee: json.optionalString('assignee'),
  );
}

/// `runs.gate`: the gate with the plan (plan gates) or the task evidence.
class const RunGateDetail({
  required final RunGate gate,
  final RunPlanView? plan,
  final List<RunGateEvidenceTask> tasks = const <RunGateEvidenceTask>[],
}) {
  factory fromJson(Map<String, Object?> json) => RunGateDetail(
    gate: RunGate.fromJson(json.mapValue('gate')),
    plan: RunPlanView.tryParse(json['plan']),
    tasks: <RunGateEvidenceTask>[
      for (final item in json.objectList('tasks'))
        RunGateEvidenceTask.fromJson(asJsonMap(item)),
    ],
  );
}

/// What `runs.resolveGate` reports back.
class const RunGateResolution({
  required final RunGate gate,
  final String? runStatus,
  final bool changesRequested = false,
  final String coordinatorAction = 'none',
}) {
  factory fromJson(Map<String, Object?> json) => RunGateResolution(
    gate: RunGate.fromJson(json.mapValue('gate')),
    runStatus: json.optionalString('runStatus'),
    changesRequested: json['changesRequested'] == true,
    coordinatorAction: json.optionalString('coordinatorAction') ?? 'none',
  );
}

class const RunTaskResult({
  final String? summary,
  final String? completionKind,
  final List<String> artifacts = const <String>[],
  final List<String> validation = const <String>[],
  final String? preview,
  final bool truncated = false,
});

class const RunTaskHistoryEntry({
  required final String id,
  required final String kind,
  required final String status,
  final DateTime? occurredAt,
  final String? summary,
});

/// The latest isolated attempt of a task.
class const RunTaskAttemptDetail({
  required final int attempt,
  final String phase = '',
  final String state = '',
  final bool canRetry = false,
  final bool canRetryIntegration = false,
  final String? executionWorkspaceId,
  final String? worktree,
  final String? branch,
  final String? completionSha,
  final String? integratedSha,
  final List<String> conflictPaths = const <String>[],
  final String? error,
});

/// `runs.task`: one task with its result, attempt, gates and history.
class const RunTaskInspection({
  required final String taskId,
  required final String runId,
  required final String title,
  required final String status,
  final String description = '',
  final bool descriptionTruncated = false,
  final String? stageId,
  final String workspaceId = '',
  final String? workspaceName,
  final String? branch,
  final String? profile,
  final String? terminalHandle,
  final List<String> dependencies = const <String>[],
  final RunTaskResult result = const RunTaskResult(),
  final List<RunTaskHistoryEntry> history = const <RunTaskHistoryEntry>[],
  final Map<String, Object?>? nextCursor,
  final RunTaskAttemptDetail? attempt,
  final List<RunGate> gates = const <RunGate>[],
}) {
  factory fromJson(Map<String, Object?> json) {
    final result = json.mapValue('result');
    final attempt = asJsonMap(json['attempt']);
    final cursor = asJsonMap(json['nextCursor']);
    return RunTaskInspection(
      taskId: json.requiredString('taskId'),
      runId: json.optionalString('runId') ?? '',
      title: json.optionalString('title') ?? json.requiredString('taskId'),
      status: json.optionalString('status') ?? 'pending',
      description: json.optionalString('description') ?? '',
      descriptionTruncated: json['descriptionTruncated'] == true,
      stageId: json.optionalString('stageId'),
      workspaceId: json.optionalString('workspaceId') ?? '',
      workspaceName: json.optionalString('workspaceName'),
      branch: json.optionalString('branch'),
      profile: json.optionalString('profile'),
      terminalHandle: json.optionalString('terminalHandle'),
      dependencies: json.stringList('dependencies'),
      result: RunTaskResult(
        summary: result.optionalString('summary'),
        completionKind: result.optionalString('completionKind'),
        artifacts: result.stringList('artifacts'),
        validation: result.stringList('validation'),
        preview: result.optionalString('preview'),
        truncated: result['truncated'] == true,
      ),
      history: <RunTaskHistoryEntry>[
        for (final item in json.objectList('history'))
          RunTaskHistoryEntry(
            id: asJsonMap(item).optionalString('id') ?? '',
            kind: asJsonMap(item).optionalString('kind') ?? '',
            status: asJsonMap(item).optionalString('status') ?? '',
            occurredAt: parseRunTimestamp(
              asJsonMap(item).optionalString('occurredAt'),
            ),
            summary: asJsonMap(item).optionalString('summary'),
          ),
      ],
      nextCursor: cursor.isEmpty ? null : cursor,
      attempt: attempt.isEmpty
          ? null
          : RunTaskAttemptDetail(
              attempt: runInt(attempt['attempt']),
              phase: attempt.optionalString('phase') ?? '',
              state: attempt.optionalString('state') ?? '',
              canRetry: attempt['canRetry'] == true,
              canRetryIntegration: attempt['canRetryIntegration'] == true,
              executionWorkspaceId: attempt.optionalString(
                'executionWorkspaceId',
              ),
              worktree: attempt.optionalString('worktree'),
              branch: attempt.optionalString('branch'),
              completionSha: attempt.optionalString('completionSha'),
              integratedSha: attempt.optionalString('integratedSha'),
              conflictPaths: attempt.stringList('conflictPaths'),
              error: attempt.optionalString('error'),
            ),
      gates: <RunGate>[
        for (final item in json.objectList('gates'))
          RunGate.fromJson(asJsonMap(item)),
      ],
    );
  }
}
