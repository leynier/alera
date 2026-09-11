import 'package:alera_mobile/src/app/app_navigation.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:flutter/material.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'background_setup_jobs.g.dart';

@Riverpod(keepAlive: true)
class BackgroundSetupJobs extends _$BackgroundSetupJobs {
  final Set<String> _inFlightIds = <String>{};
  var _retryOpening = false;

  @override
  BackgroundSetupJobsState build() => const BackgroundSetupJobsState();

  void dismiss(String jobId) {
    state = state.withoutJob(jobId);
  }

  void beginForm() {
    state = state.withFormLockCount(state.formLockCount + 1);
  }

  void endForm() {
    if (!ref.mounted) {
      return;
    }
    state = state.withFormLockCount(state.formLockCount - 1);
  }

  bool beginRetryNavigation() {
    if (_retryOpening) {
      return false;
    }
    _retryOpening = true;
    beginForm();
    return true;
  }

  void endRetryNavigation() {
    if (!_retryOpening) {
      return;
    }
    _retryOpening = false;
    endForm();
  }

  Future<WorkspaceCreationResult> enqueueManualWorkspace(
    ManualWorkspaceCreateRequest request, {
    String? jobId,
  }) async {
    final id = jobId ?? 'job-${DateTime.now().microsecondsSinceEpoch}';
    if (!_inFlightIds.add(id)) {
      throw StateError('Workspace creation is already running.');
    }
    state = state.withJob(
      BackgroundSetupJob(
        id: id,
        kind: .manualWorkspace,
        status: .running,
        title: 'Creating workspace "${request.displayName}"',
        phase: 'Creating workspace',
        snapshot: request,
      ),
    );
    late final WorkspaceCreationResult result;
    try {
      await _run(id, () async {
        result = await ref
            .read(workspaceListControllerProvider(request.hostId).notifier)
            .createWorkspace(
              projectId: request.projectId,
              branch: request.branch,
              sourceBranch: request.sourceBranch,
              reuseExistingBranch: request.reuseExistingBranch,
              name: request.name,
              parentWorkspaceId: request.parentWorkspaceId,
            );
        _publishWorkspaceCreatedIfDetached(result);
      });
      return result;
    } finally {
      _inFlightIds.remove(id);
    }
  }

  Future<PromptWorkspaceCreateOutcome> enqueuePromptWorkspace(
    PromptWorkspaceCreateRequest request, {
    String? jobId,
  }) async {
    final id = jobId ?? 'job-${DateTime.now().microsecondsSinceEpoch}';
    if (!_inFlightIds.add(id)) {
      throw StateError('Workspace creation is already running.');
    }
    final existingSnapshot = state.jobById(id)?.snapshot;
    final requestToRun =
        existingSnapshot is PromptWorkspaceCreateRequest &&
            existingSnapshot.created != null &&
            existingSnapshot.matchesLaunchTarget(request)
        ? request.withCreated(
            existingSnapshot.created!,
            clientMutationId: existingSnapshot.clientMutationId,
            originalLaunchWasIdempotent:
                existingSnapshot.originalLaunchWasIdempotent,
            setupStarted: existingSnapshot.setupStarted,
          )
        : request;
    final clientMutationId =
        requestToRun.clientMutationId ??
        'mobile-agent-launch-${DateTime.now().microsecondsSinceEpoch}';
    state = state.withJob(
      BackgroundSetupJob(
        id: id,
        kind: .promptWorkspace,
        status: .running,
        title: requestToRun.created == null
            ? 'Creating workspace from prompt'
            : 'Starting agent',
        phase: requestToRun.created == null
            ? 'Generating workspace identity'
            : 'Starting agent',
        snapshot: requestToRun,
      ),
    );
    late final PromptWorkspaceCreateOutcome result;
    final keepClient = ref.listen(
      workspaceClientProvider(request.hostId),
      (_, _) {},
    );
    final keepTerminal = ref.listen(
      terminalClientProvider(request.hostId),
      (_, _) {},
    );
    try {
      await _run(id, () async {
        final client = await ref.read(
          workspaceClientProvider(request.hostId).future,
        );
        try {
          final outcome = await runPromptWorkspaceCreate(
            client: client,
            loadTerminalClient: () =>
                ref.read(terminalClientProvider(request.hostId).future),
            request: requestToRun,
            clientMutationId: clientMutationId,
            onPhase: (phase) {
              final job = state.jobById(id);
              if (job == null) {
                return;
              }
              state = state.withJob(
                BackgroundSetupJob(
                  id: job.id,
                  kind: job.kind,
                  status: job.status,
                  title: phase == 'Starting agent'
                      ? 'Starting agent'
                      : job.title,
                  snapshot: job.snapshot,
                  phase: phase,
                  error: job.error,
                ),
              );
            },
          );
          result = outcome;
          _publishWorkspaceCreatedIfDetached(outcome.creation);
        } on PromptWorkspaceLaunchException catch (failure) {
          final job = state.jobById(id);
          if (job != null) {
            state = state.withJob(
              BackgroundSetupJob(
                id: job.id,
                kind: job.kind,
                status: job.status,
                title: job.title,
                snapshot: requestToRun.withCreated(
                  failure.creation,
                  clientMutationId: failure.clientMutationId,
                  originalLaunchWasIdempotent:
                      failure.originalLaunchWasIdempotent,
                  setupStarted: failure.setupStarted,
                ),
                phase: job.phase,
                error: job.error,
              ),
            );
          }
          rethrow;
        }
      });
      return result;
    } finally {
      keepClient.close();
      keepTerminal.close();
      _inFlightIds.remove(id);
    }
  }

  Future<void> _run(String jobId, Future<void> Function() action) async {
    try {
      await action();
      state = state.withoutJob(jobId);
    } catch (error) {
      final job = state.jobById(jobId);
      if (job != null) {
        state = state.withJob(
          BackgroundSetupJob(
            id: job.id,
            kind: job.kind,
            status: .failed,
            title: job.title,
            snapshot: job.snapshot,
            error: error.toString(),
          ),
        );
      }
      rethrow;
    }
  }

  void _publishWorkspaceCreatedIfDetached(WorkspaceCreationResult creation) {
    final message = creation.setupLaunchError != null
        ? 'Workspace created, but setup could not start'
        : creation.hasSetupWarnings
        ? 'Workspace created with setup warnings'
        : creation.parentLinkError != null
        ? 'Workspace created, but parent link failed'
        : 'Workspace created';
    final context = aleraNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
