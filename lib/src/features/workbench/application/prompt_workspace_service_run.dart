import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_service_client.dart';
import 'package:alera/src/features/workbench/infra/runtime_managed_workspace_client.dart';

/// A runtime operation that ended without completing. [creation] is set when
/// the workspace exists, so the job can still show it and retry the launch.
class PromptWorkspaceServiceFailure implements Exception {
  PromptWorkspaceServiceFailure(this.operation, {this.creation});

  final PromptWorkspaceOperation operation;
  final WorkspaceCreationResult? creation;

  @override
  String toString() => operation.failureMessage;
}

class const PromptWorkspaceServiceOutcome({
  required final PromptWorkspaceOperation operation,
  required final WorkspaceCreationResult creation,
}) {
  String? get agentTabId => operation.agentTabId;
}

/// Whether [request] can run on the runtime service: a fresh request always
/// can, a launch retry only when the service created that workspace.
bool canRunPromptWorkspaceOnService(PromptWorkspaceCreateRequest request) =>
    request.created == null || request.serviceOperationId != null;

/// The idempotency key of one submission of a background job. The same job,
/// attempt, and form values map to the same runtime operation, so a repeated
/// submission follows the running operation instead of creating a second
/// workspace; a later attempt or edited form starts a new one.
String promptWorkspaceServiceRequestId({
  required String jobId,
  required int attempt,
  required PromptWorkspaceCreateRequest request,
}) {
  final fingerprint = _fnv1a(
    <Object?>[
      request.project.id,
      request.prompt.trim(),
      request.profileId,
      request.useProjectCheckout,
      request.sourceBranch,
      request.hostId,
      request.parentWorkspaceId,
      request.issueUrl,
      request.autoAssignSection,
    ].join('\u0000'),
  );
  return 'desktop-prompt-workspace:$jobId:$attempt:$fingerprint';
}

Map<String, Object?> promptWorkspaceStartPayload(
  PromptWorkspaceCreateRequest request, {
  required String requestId,
}) {
  final sourceBranch = request.sourceBranch.trim();
  return <String, Object?>{
    'prompt': request.prompt.trim(),
    'projectId': request.project.id,
    'profile': request.profileId,
    'mode': request.useProjectCheckout ? 'projectCheckout' : 'worktree',
    if (!request.useProjectCheckout && sourceBranch.isNotEmpty)
      'sourceBranch': sourceBranch,
    'hostId': ?normalizedRemoteHostId(request.hostId),
    'parentWorkspaceId': ?_nonEmpty(request.parentWorkspaceId),
    'issueUrl': ?_nonEmpty(request.issueUrl),
    'section': request.autoAssignSection ? 'auto' : 'none',
    'requestId': requestId,
    'origin': const <String, Object?>{'surface': 'desktop'},
  };
}

/// Starts [request] on the runtime, or relaunches the agent of the operation
/// that created its workspace, and follows it to the end.
Future<PromptWorkspaceServiceOutcome> runPromptWorkspaceService({
  required PromptWorkspaceServiceClient service,
  required PromptWorkspaceCreateRequest request,
  required String requestId,
  void Function(String phase)? onPhase,
}) async {
  final retryOperationId = request.created == null
      ? null
      : request.serviceOperationId;
  final started = retryOperationId == null
      ? await service.start(
          promptWorkspaceStartPayload(request, requestId: requestId),
        )
      : await service.retryLaunch(retryOperationId);
  final operation = await service.follow(
    started,
    onUpdate: (operation) {
      if (operation.isRunning) {
        onPhase?.call(promptWorkspacePhaseLabel(operation.phase));
      }
    },
  );
  final workspace = operation.workspace;
  final creation = workspace == null
      ? null
      : workspaceCreationResultFromRuntime(<String, Object?>{
          'workspace': workspace,
          'setupReport': const <String, Object?>{},
        });
  if (operation.status == PromptWorkspaceOperationStatus.completed &&
      creation != null) {
    return PromptWorkspaceServiceOutcome(
      operation: operation,
      creation: creation,
    );
  }
  throw PromptWorkspaceServiceFailure(operation, creation: creation);
}

/// One background job on the runtime service. Returns null, having called
/// nothing, when the runtime cannot run [request]; the caller then runs the
/// client-side pipeline.
///
/// [showWorkspace] brings the created workspace into the workbench with the
/// tab to select; the host already created and started its Setup tab. On a
/// failure after creation, [onWorkspaceKept] receives the job snapshot whose
/// retry relaunches the agent on the host before the failure is rethrown.
Future<PromptWorkspaceServiceOutcome?> runPromptWorkspaceJobOnService({
  required PromptWorkspaceServiceClient service,
  required PromptWorkspaceCreateRequest request,
  required String requestId,
  required Future<void> Function(
    WorkspaceCreationResult creation,
    String? selectTabId,
  )
  showWorkspace,
  void Function(String phase)? onPhase,
  void Function(PromptWorkspaceCreateRequest snapshot)? onWorkspaceKept,
}) async {
  if (!canRunPromptWorkspaceOnService(request) ||
      !await service.isSupported()) {
    return null;
  }
  try {
    final outcome = await runPromptWorkspaceService(
      service: service,
      request: request,
      requestId: requestId,
      onPhase: onPhase,
    );
    onPhase?.call('Starting agent');
    await showWorkspace(outcome.creation, outcome.agentTabId);
    return outcome;
  } on PromptWorkspaceServiceFailure catch (failure) {
    final creation = failure.creation;
    if (creation != null) {
      onWorkspaceKept?.call(
        request.withCreated(creation, serviceOperationId: failure.operation.id),
      );
      try {
        await showWorkspace(creation, failure.operation.setupTabId);
      } catch (_) {
        // The workspace list refresh still brings it in; the job reports the
        // launch failure either way.
      }
    }
    rethrow;
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
