import 'dart:async';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';

enum PromptWorkspaceOperationStatus {
  running,
  needsInput,
  completed,
  failed,
  cancelled;

  static PromptWorkspaceOperationStatus parse(Object? value) {
    for (final status in values) {
      if (status.name == value) {
        return status;
      }
    }
    return failed;
  }
}

/// One `workspace.promptStart` operation as the runtime reports it.
class const PromptWorkspaceOperation({
  required final String id,
  required final PromptWorkspaceOperationStatus status,
  required final String phase,
  final Map<String, Object?>? workspace,
  final String? agentTabId,
  final String? setupTabId,
  final String? setupCommand,
  final List<String> warnings = const <String>[],
  final String? errorMessage,
}) {
  factory fromJson(Map<String, Object?> json) {
    final workspace = json['workspace'] is Map
        ? json.mapValue('workspace')
        : null;
    final setup = json.mapValue('setup');
    return PromptWorkspaceOperation(
      id: json.requiredString('id'),
      status: .parse(json['status']),
      phase: json.optionalString('phase') ?? '',
      workspace: workspace?.optionalString('id') == null ? null : workspace,
      agentTabId: json.mapValue('agent').optionalString('tabId'),
      setupTabId: setup.optionalString('tabId'),
      setupCommand: setup.optionalString('command'),
      warnings: <String>[
        for (final warning in json.stringList('warnings'))
          if (warning.trim().isNotEmpty) warning,
      ],
      errorMessage: json.mapValue('error').optionalString('message'),
    );
  }

  bool get isRunning => status == PromptWorkspaceOperationStatus.running;

  String get failureMessage => switch (status) {
    .cancelled => 'Workspace creation was cancelled.',
    .needsInput =>
      errorMessage ?? 'The runtime needs more input to create this workspace.',
    _ => errorMessage ?? 'Workspace creation failed.',
  };

  /// The workspace as the job shows it. The host starts the Setup tab itself,
  /// so the result carries no deferred command for the phone to run; when the
  /// host could not start it, the warning is reported instead.
  WorkspaceCreationResult? get creation {
    final json = workspace;
    if (json == null) {
      return null;
    }
    final creation = WorkspaceCreationResult.fromJson(<String, Object?>{
      'workspace': json,
    });
    if (setupTabId == null && setupCommand != null) {
      return creation.withSetupLaunchError(
        warnings.isEmpty ? 'The worktree setup did not start.' : warnings.first,
      );
    }
    return creation;
  }
}

/// A runtime operation that ended without completing and without a workspace.
class PromptWorkspaceServiceFailure implements Exception {
  PromptWorkspaceServiceFailure(this.operation);

  final PromptWorkspaceOperation operation;

  @override
  String toString() => operation.failureMessage;
}

/// The job phase for a runtime phase, using the same text as the client-side
/// pipeline so both paths read alike.
String promptWorkspacePhaseLabel(String phase) => switch (phase) {
  'resolvingProject' || 'generatingIdentity' => 'Generating workspace identity',
  'checkingBranch' => 'Checking generated branch',
  'creatingWorkspace' || 'assigningSection' => 'Creating workspace',
  'startingSetup' => 'Starting setup',
  _ => 'Starting agent',
};

/// The service surface of [client] when its runtime advertises
/// [promptWorkspaceServiceCapability], else null.
MobilePromptWorkspaceServiceClient? promptWorkspaceServiceOf(Object client) {
  if (client case final MobilePromptWorkspaceServiceClient service
      when service.runtimeCapabilities.contains(
        promptWorkspaceServiceCapability,
      )) {
    return service;
  }
  return null;
}

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
      request.projectId,
      request.prompt.trim(),
      request.profileId,
      request.useProjectCheckout,
      request.sourceBranch,
      request.checkoutHostId,
      request.parentWorkspaceId,
      request.issueUrl,
      request.autoAssignSection,
    ].join('\u0000'),
  );
  return 'mobile-prompt-workspace:$jobId:$attempt:$fingerprint';
}

Map<String, Object?> promptWorkspaceStartPayload(
  PromptWorkspaceCreateRequest request, {
  required String requestId,
}) {
  final sourceBranch = request.sourceBranch.trim();
  final hostId = _nonEmpty(request.checkoutHostId);
  return <String, Object?>{
    'prompt': request.prompt.trim(),
    'projectId': request.projectId,
    'profile': request.profileId,
    'mode': request.useProjectCheckout ? 'projectCheckout' : 'worktree',
    if (!request.useProjectCheckout && sourceBranch.isNotEmpty)
      'sourceBranch': sourceBranch,
    if (hostId != null && hostId != 'local') 'hostId': hostId,
    'parentWorkspaceId': ?_nonEmpty(request.parentWorkspaceId),
    'issueUrl': ?_nonEmpty(request.issueUrl),
    'section': request.autoAssignSection ? 'auto' : 'none',
    'requestId': requestId,
    'origin': const <String, Object?>{'surface': 'mobile'},
  };
}

/// Starts [request] on the runtime, or relaunches the agent of the operation
/// that created its workspace, and follows it until it leaves `running`.
///
/// Each `promptWorkspaceOperationsChanged` for the operation triggers a read;
/// until one arrives the operation is polled every [pollInterval], since an
/// older or interrupted event stream would otherwise leave the job waiting.
Future<PromptWorkspaceOperation> runPromptWorkspaceOperation(
  MobilePromptWorkspaceServiceClient service, {
  required PromptWorkspaceCreateRequest request,
  required String requestId,
  void Function(String phase)? onPhase,
  Duration pollInterval = const Duration(seconds: 1),
  Duration eventSafetyInterval = const Duration(seconds: 10),
  int maxConsecutiveReadFailures = 3,
}) async {
  final retryOperationId = request.created == null
      ? null
      : request.serviceOperationId;
  var current = PromptWorkspaceOperation.fromJson(
    retryOperationId == null
        ? await service.requestMap(
            'workspace.promptStart.start',
            promptWorkspaceStartPayload(request, requestId: requestId),
          )
        : await service.requestMap(
            'workspace.promptStart.retryLaunch',
            <String, Object?>{'id': retryOperationId},
          ),
  );
  if (!current.isRunning) {
    return current;
  }
  onPhase?.call(promptWorkspacePhaseLabel(current.phase));
  var wake = Completer<void>();
  var eventsSeen = false;
  final subscription = service.events.listen((event) {
    if (event.name != promptWorkspaceOperationsChangedEvent ||
        event.payload['id'] != current.id) {
      return;
    }
    eventsSeen = true;
    if (!wake.isCompleted) {
      wake.complete();
    }
  });
  var failures = 0;
  try {
    while (current.isRunning) {
      await Future.any(<Future<void>>[
        wake.future,
        Future.pause(eventsSeen ? eventSafetyInterval : pollInterval),
      ]);
      wake = Completer<void>();
      try {
        current = PromptWorkspaceOperation.fromJson(
          await service.requestMap(
            'workspace.promptStart.get',
            <String, Object?>{'id': current.id},
          ),
        );
        failures = 0;
      } on Object {
        failures += 1;
        if (failures >= maxConsecutiveReadFailures) {
          rethrow;
        }
        continue;
      }
      if (current.isRunning) {
        onPhase?.call(promptWorkspacePhaseLabel(current.phase));
      }
    }
    return current;
  } finally {
    await subscription.cancel();
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
