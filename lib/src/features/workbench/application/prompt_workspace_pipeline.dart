import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:uuid/uuid.dart';

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

class const PromptWorkspacePipeline({
  required final Future<GeneratedWorkspaceIdentity> Function({
    required String operationId,
    required String projectId,
    required String prompt,
  })
  generateIdentity,
  required final Future<bool> Function(Project project, String branchName)
  checkBranchExists,
  required final Set<String> Function(Project project) workspaceBranches,
  required final Future<WorkspaceCreationResult> Function({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required String name,
    String? parentWorkspaceId,
    String? hostId,
    String? issueUrl,
  })
  createWorkspace,
  required final Future<AgentProfileLaunchResult> Function({
    required String workspaceId,
    required String profileId,
    required String prompt,
    required String clientMutationId,
    required bool requireIdempotency,
  })
  launchAgent,
  final void Function(String phase)? onPhase,
  final String Function()? createOperationId,
}) {
  Future<PromptWorkspacePipelineResult> run(
    PromptWorkspaceCreateRequest request,
  ) async {
    final prompt = request.prompt.trim();
    WorkspaceCreationResult? creation = request.created;
    Object? collisionError;
    for (var attempt = 0; creation == null && attempt < 2; attempt++) {
      final identityPrompt = attempt == 0
          ? prompt
          : '$prompt\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch.';
      onPhase?.call('Generating workspace identity');
      final identity = await generateIdentity(
        operationId: createOperationId?.call() ?? const Uuid().v4(),
        projectId: request.project.id,
        prompt: identityPrompt,
      );
      onPhase?.call('Checking generated branch');
      final collision =
          workspaceBranches(request.project).contains(identity.branchName) ||
          await checkBranchExists(request.project, identity.branchName);
      if (collision) {
        collisionError = StateError(
          'The generated branch "${identity.branchName}" already exists.',
        );
        continue;
      }
      onPhase?.call('Creating workspace');
      try {
        creation = await createWorkspace(
          project: request.project,
          sourceBranch: request.sourceBranch,
          newBranchName: identity.branchName,
          name: identity.workspaceName,
          parentWorkspaceId: request.parentWorkspaceId,
          hostId: request.hostId,
          issueUrl: request.issueUrl,
        );
        break;
      } catch (error) {
        if (attempt == 0 && _looksLikeCollision(error)) {
          collisionError = error;
          continue;
        }
        throw StateError(userFacingExceptionMessage(error));
      }
    }
    if (creation == null) {
      throw collisionError ??
          StateError(
            'AI Assist could not generate an available workspace identity.',
          );
    }
    if (request.created != null &&
        request.originalLaunchWasIdempotent != true) {
      throw UnsupportedError(
        'Update Alera on this host before retrying agent launch safely.',
      );
    }
    onPhase?.call('Starting agent');
    final clientMutationId =
        request.clientMutationId ??
        createOperationId?.call() ??
        const Uuid().v4();
    try {
      final launch = await launchAgent(
        workspaceId: creation.workspace.id,
        profileId: request.profileId,
        prompt: prompt,
        clientMutationId: clientMutationId,
        requireIdempotency: request.created != null,
      );
      return PromptWorkspacePipelineResult(
        creation: creation,
        agentTabId: launch.tabId,
        clientMutationId: clientMutationId,
        originalLaunchWasIdempotent: launch.idempotent,
      );
    } catch (error) {
      throw PromptWorkspaceLaunchException(
        creation: creation,
        cause: error,
        clientMutationId: clientMutationId,
        setupStarted: request.setupStarted,
        originalLaunchWasIdempotent: error is NonIdempotentAgentLaunchFailure
            ? false
            : (request.originalLaunchWasIdempotent ?? true),
      );
    }
  }
}

bool _looksLikeCollision(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('already exists') ||
      message.contains('workspace for branch');
}
