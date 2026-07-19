import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

class WorkspaceSetupStep {
  const WorkspaceSetupStep({
    required this.kind,
    required this.label,
    required this.succeeded,
    this.message,
    this.exitCode,
  });

  final String kind;
  final String label;
  final bool succeeded;
  final String? message;
  final int? exitCode;

  factory WorkspaceSetupStep.fromJson(Map<String, Object?> json) {
    return WorkspaceSetupStep(
      kind: json.optionalString('kind') ?? 'config',
      label: json.requiredString('label'),
      succeeded: json['succeeded'] == true,
      message: json.optionalString('message'),
      exitCode: (json['exitCode'] as num?)?.toInt(),
    );
  }
}

class WorkspaceCreationResult {
  const WorkspaceCreationResult({required this.workspace, required this.steps});

  final WorkspaceSummary workspace;
  final List<WorkspaceSetupStep> steps;

  factory WorkspaceCreationResult.fromJson(Map<String, Object?> json) {
    return WorkspaceCreationResult(
      workspace: WorkspaceSummary.fromJson(json.mapValue('workspace')),
      steps: <WorkspaceSetupStep>[
        for (final item in json.mapValue('setupReport').objectList('steps'))
          if (item is Map) WorkspaceSetupStep.fromJson(asJsonMap(item)),
      ],
    );
  }
}
