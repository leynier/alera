import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';

class PromptWorkspaceLaunchException implements Exception {
  PromptWorkspaceLaunchException({
    required this.creation,
    required this.cause,
    this.clientMutationId,
    this.setupStarted = false,
    this.originalLaunchWasIdempotent,
  });

  final WorkspaceCreationResult creation;
  final Object cause;
  final String? clientMutationId;
  final bool setupStarted;
  final bool? originalLaunchWasIdempotent;

  @override
  String toString() => cause.toString();
}

class const PromptWorkspaceCreateOutcome({
  required final WorkspaceCreationResult creation,
  required final String agentTabId,
});

Future<PromptWorkspaceCreateOutcome> runPromptWorkspaceCreate({
  required MobileWorkspaceClient client,
  required Future<MobileTerminalClient> Function() loadTerminalClient,
  required PromptWorkspaceCreateRequest request,
  required String clientMutationId,
  void Function(String phase)? onPhase,
  void Function(String? operationId)? onOperationId,
  void Function(WorkspaceCreationResult creation)? onWorkspaceCreated,
}) async {
  final prompt = request.prompt.trim();
  if (prompt.isEmpty) {
    throw StateError(
      'Complete the prompt, project, branch, and agent profile.',
    );
  }
  WorkspaceCreationResult? creation = request.created;
  Object? collisionError;
  for (var attempt = 0; creation == null && attempt < 2; attempt++) {
    final identityPrompt = attempt == 0
        ? prompt
        : '$prompt\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch.';
    onPhase?.call('Generating workspace identity');
    final operationId =
        'mobile-${DateTime.now().microsecondsSinceEpoch}-$attempt';
    onOperationId?.call(operationId);
    late final GeneratedWorkspaceIdentity identity;
    try {
      identity = await client.generateWorkspaceIdentity(
        operationId: operationId,
        projectId: request.projectId,
        prompt: identityPrompt,
      );
    } finally {
      onOperationId?.call(null);
    }
    onPhase?.call('Checking generated branch');
    final branches = await client.listBranches(request.projectId);
    if (request.workspaceBranches.contains(identity.branchName) ||
        branches.branches.contains(identity.branchName)) {
      collisionError = StateError(
        'The generated branch "${identity.branchName}" already exists.',
      );
      continue;
    }
    onPhase?.call('Creating workspace');
    try {
      final created = await client.createManagedWorkspace(
        projectId: request.projectId,
        branch: identity.branchName,
        sourceBranch: request.sourceBranch,
        name: identity.workspaceName,
      );
      creation = created;
      final parentId = request.parentWorkspaceId?.trim();
      if (parentId != null && parentId.isNotEmpty) {
        try {
          await client.linkWorkspaces(
            parentWorkspaceId: parentId,
            childWorkspaceId: created.workspace.id,
          );
        } on Object catch (error) {
          creation = created.withParentLinkError(error);
        }
      }
      break;
    } on Object catch (error) {
      if (attempt == 0 && _looksLikeCollision(error)) {
        collisionError = error;
        continue;
      }
      rethrow;
    }
  }
  if (creation == null) {
    throw collisionError ??
        StateError(
          'AI Assist could not generate an available workspace identity.',
        );
  }
  if (request.created != null &&
      (request.originalLaunchWasIdempotent != true ||
          !client.supportsIdempotentAgentProfileLaunch)) {
    throw UnsupportedError(
      'Update Alera on this host before retrying agent launch safely.',
    );
  }
  onPhase?.call('Starting agent');
  onWorkspaceCreated?.call(creation);
  final originalLaunchWasIdempotent =
      request.originalLaunchWasIdempotent ??
      client.supportsIdempotentAgentProfileLaunch;
  var setupStarted = request.setupStarted;
  try {
    final launch = await client.launchAgentProfile(
      workspaceId: creation.workspace.id,
      profileId: request.profileId,
      prompt: prompt,
      clientMutationId: clientMutationId,
    );
    var completedCreation = creation;
    if (creation.hasDeferredSetup && !setupStarted) {
      onPhase?.call('Starting setup');
      final terminalClient = await loadTerminalClient();
      completedCreation = await launchDeferredWorkspaceSetup(
        terminalClient,
        creation,
      );
      setupStarted = true;
    }
    return PromptWorkspaceCreateOutcome(
      creation: completedCreation,
      agentTabId: launch.tabId,
    );
  } catch (error) {
    var completedCreation = creation;
    if (creation.hasDeferredSetup && !setupStarted) {
      onPhase?.call('Starting setup');
      try {
        final terminalClient = await loadTerminalClient();
        completedCreation = await launchDeferredWorkspaceSetup(
          terminalClient,
          creation,
        );
        setupStarted = true;
      } catch (_) {}
    }
    throw PromptWorkspaceLaunchException(
      creation: completedCreation,
      cause: error,
      clientMutationId: clientMutationId,
      setupStarted: setupStarted,
      originalLaunchWasIdempotent: originalLaunchWasIdempotent,
    );
  }
}

bool _looksLikeCollision(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('already exists') ||
      message.contains('workspace for branch');
}
