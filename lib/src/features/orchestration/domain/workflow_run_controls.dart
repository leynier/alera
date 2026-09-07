class WorkflowRunControls {
  WorkflowRunControls.fromJson(Map<String, Object?> json)
    : runId = json['runId']! as String,
      revision = json['revision']! as int,
      status = json['status']! as String,
      canControl = json['canControl']! as bool,
      canCancel = json['canCancel']! as bool,
      canCorrect = json['canCorrect']! as bool,
      cancellationPending = json['cancellationPending']! as int,
      cancellationError = json['cancellationError'] as String?,
      integrationSha = json['integrationSha']! as String,
      sourceSha = json['sourceSha']! as String,
      recipeName = json['recipeName']! as String,
      recipeOrigin = _origin(json['recipeSource']! as Map),
      execution = json['execution'] == null
          ? null
          : WorkflowExecutionState.fromJson(json['execution']! as Map),
      stages = List.unmodifiable(
        (json['stages']! as List).map(
          (value) => WorkflowStageControl.fromJson(value as Map),
        ),
      ) {
    if (revision < 1 ||
        stages.length > 16 ||
        (execution != null &&
            (execution!.runId != runId || execution!.revision != revision))) {
      throw const FormatException('Invalid workflow control snapshot.');
    }
  }

  final String runId;
  final int revision;
  final String status;
  final bool canControl;
  final bool canCancel;
  final bool canCorrect;
  final int cancellationPending;
  final String? cancellationError;
  final String integrationSha;
  final String sourceSha;
  final String recipeName;
  final String recipeOrigin;
  final WorkflowExecutionState? execution;
  final List<WorkflowStageControl> stages;
}

class WorkflowExecutionState {
  WorkflowExecutionState.fromJson(Map json)
    : runId = json['runId']! as String,
      revision = json['revision']! as int,
      sequence = json['sequence']! as int,
      status = json['status']! as String,
      attention = json['attention'] as String? {
    if (sequence < 0) throw const FormatException('Invalid workflow sequence.');
  }
  final String runId;
  final int revision;
  final int sequence;
  final String status;
  final String? attention;
}

class WorkflowStageControl {
  WorkflowStageControl.fromJson(Map json)
    : id = json['id']! as String,
      name = json['name']! as String,
      dependsOn = List.unmodifiable(
        (json['dependsOn']! as List).cast<String>(),
      ),
      gate = json['gate'] as String?,
      gateStatus = json['gateStatus'] as String?,
      canReview = json['canReview']! as bool,
      taskCount = json['taskCount']! as int,
      integratedCount = json['integratedCount']! as int;
  final String id;
  final String name;
  final List<String> dependsOn;
  final String? gate;
  final String? gateStatus;
  final bool canReview;
  final int taskCount;
  final int integratedCount;
}

String _origin(Map source) => switch (source['origin']) {
  'builtIn' => 'Built-in',
  'personal' => 'Personal',
  'project' => 'Project: ${source['path']}',
  _ => throw const FormatException('Unknown workflow recipe origin.'),
};
