part of 'background_setup_jobs.dart';

/// New Workspace from Prompt on a runtime that runs it as an operation
/// (`promptWorkspaceServiceV1`): the host generates the identity, creates the
/// workspace, launches the agent and starts the Setup tab, and the job only
/// follows it and shows the result.
mixin _BackgroundSetupJobsPromptService
    on _$BackgroundSetupJobs, _BackgroundSetupJobsInternals {
  /// Submissions of each job that ended without completing; the next one
  /// needs a fresh runtime operation.
  final Map<String, int> _promptServiceAttempts = <String, int>{};

  /// Returns false when the runtime has no service for [request], so the
  /// caller runs the client-side pipeline instead.
  Future<bool> _runPromptWorkspaceOnService(
    String jobId,
    PromptWorkspaceCreateRequest request,
  ) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final attempt = _promptServiceAttempts[jobId] ?? 0;
    final PromptWorkspaceServiceOutcome? outcome;
    try {
      outcome = await runPromptWorkspaceJobOnService(
        service: PromptWorkspaceServiceClient(
          ref.read(runtimeHostClientProvider),
          beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
        ),
        request: request,
        requestId: promptWorkspaceServiceRequestId(
          jobId: jobId,
          attempt: attempt,
          request: request,
        ),
        onPhase: (phase) => _setPhase(jobId, phase),
        showWorkspace: (creation, selectTabId) async {
          controller.reconcileRuntimeCreatedWorkspace(creation.workspace);
          await controller.completePromptWorkspaceCreation(
            creation: creation,
            agentTabId: selectTabId,
            openDeferredSetup: false,
          );
        },
        onWorkspaceKept: (snapshot) => _upsert(
          BackgroundSetupJob(
            id: jobId,
            kind: .promptWorkspace,
            status: .running,
            title: 'Starting agent',
            phase: 'Starting agent',
            snapshot: snapshot,
          ),
        ),
      );
    } on PromptWorkspaceServiceFailure {
      _promptServiceAttempts[jobId] = attempt + 1;
      rethrow;
    }
    if (outcome == null) {
      return false;
    }
    _promptServiceAttempts.remove(jobId);
    _publishPromptServiceWorkspace(outcome.creation, outcome.operation);
    return true;
  }

  void _publishPromptServiceWorkspace(
    WorkspaceCreationResult creation,
    PromptWorkspaceOperation operation,
  ) {
    if (operation.warnings.isEmpty) {
      _publishWorkspaceCreated(creation);
      return;
    }
    AleraToast.publish(
      message: 'Workspace created with warnings: ${operation.warnings.first}',
      tone: .warning,
      duration: AleraToast.longDuration,
    );
  }
}
