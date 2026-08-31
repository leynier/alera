import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

class const WorkspaceSetupStep({
  required final String kind,
  required final String label,
  required final bool succeeded,
  final String? message,
  final int? exitCode,
}) {
  factory fromJson(Map<String, Object?> json) {
    return WorkspaceSetupStep(
      kind: json.optionalString('kind') ?? 'config',
      label: json.requiredString('label'),
      succeeded: json['succeeded'] == true,
      message: json.optionalString('message'),
      exitCode: (json['exitCode'] as num?)?.toInt(),
    );
  }
}

class const WorkspaceCreationResult({
  required final WorkspaceSummary workspace,
  required final List<WorkspaceSetupStep> steps,
  final String? deferredSetupCommand,
  final String? setupLaunchError,
  final String? parentLinkError,
}) {
  bool get hasDeferredSetup =>
      deferredSetupCommand != null && deferredSetupCommand!.trim().isNotEmpty;

  bool get hasSetupWarnings =>
      setupLaunchError != null || steps.any((step) => !step.succeeded);

  WorkspaceCreationResult withSetupLaunchError(Object error) {
    return WorkspaceCreationResult(
      workspace: workspace,
      steps: steps,
      deferredSetupCommand: deferredSetupCommand,
      setupLaunchError: error.toString(),
      parentLinkError: parentLinkError,
    );
  }

  WorkspaceCreationResult withParentLinkError(Object error) {
    return WorkspaceCreationResult(
      workspace: workspace,
      steps: steps,
      deferredSetupCommand: deferredSetupCommand,
      setupLaunchError: setupLaunchError,
      parentLinkError: error.toString(),
    );
  }

  factory fromJson(Map<String, Object?> json) {
    return WorkspaceCreationResult(
      workspace: .fromJson(json.mapValue('workspace')),
      steps: <WorkspaceSetupStep>[
        for (final item in json.mapValue('setupReport').objectList('steps'))
          if (item is Map) WorkspaceSetupStep.fromJson(asJsonMap(item)),
      ],
      deferredSetupCommand: json.optionalString('deferredSetupCommand'),
      parentLinkError: json.optionalString('parentLinkError'),
    );
  }
}
