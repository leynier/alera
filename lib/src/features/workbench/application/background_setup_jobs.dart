import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_clone_job.dart';
import 'package:alera/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'background_setup_jobs.g.dart';
part 'background_setup_jobs_clone.dart';

@Riverpod(keepAlive: true)
class BackgroundSetupJobs extends _$BackgroundSetupJobs
    with _BackgroundSetupJobsInternals, _BackgroundSetupJobsClone {
  @override
  BackgroundSetupJobsState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_runtimeEvents?.cancel());
    });
    _runtimeEvents = ref.watch(runtimeHostClientProvider).runtimeEvents.listen((
      event,
    ) {
      if (event.name == 'projectCloneJobsChanged' ||
          event.name == 'projectsChanged') {
        unawaited(_refreshCloneJobs());
      }
    });
    unawaited(_refreshCloneJobs());
    return const BackgroundSetupJobsState();
  }

  void dismiss(String jobId) {
    final job = state.jobById(jobId);
    if (job != null && job.kind == .projectClone) {
      _dismissedCloneIds.add(job.runtimeJobId ?? job.id);
    }
    state = state.withoutJob(jobId);
  }

  void beginForm() {
    state = state.withFormLockCount(state.formLockCount + 1);
  }

  void endForm() {
    state = state.withFormLockCount(state.formLockCount - 1);
  }

  Future<void>? enqueueManualWorkspace(
    ManualWorkspaceCreateRequest request, {
    String? jobId,
  }) {
    final id = jobId ?? const Uuid().v4();
    if (!_inFlightIds.add(id)) {
      return null;
    }
    _upsert(
      BackgroundSetupJob(
        id: id,
        kind: .manualWorkspace,
        status: .running,
        title: 'Creating workspace "${request.displayName}"',
        phase: 'Creating workspace',
        snapshot: request,
      ),
    );
    return _run(id, () async {
      final result = await ref
          .read(workbenchControllerProvider.notifier)
          .createWorkspace(
            project: request.project,
            sourceBranch: request.sourceBranch,
            newBranchName: request.newBranchName,
            reuseExistingBranch: request.reuseExistingBranch,
            name: request.name,
            parentWorkspaceId: request.parentWorkspaceId,
            hostId: request.hostId,
          );
      _publishWorkspaceCreated(result);
    }).whenComplete(() {
      _inFlightIds.remove(id);
    });
  }

  Future<void>? enqueuePromptWorkspace(
    PromptWorkspaceCreateRequest request, {
    String? jobId,
  }) {
    final id = jobId ?? const Uuid().v4();
    if (!_inFlightIds.add(id)) {
      return null;
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
    _upsert(
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
    return _run(id, () async {
      final controller = ref.read(workbenchControllerProvider.notifier);
      final runtime = PromptWorkspaceRuntimeClient(
        ref.read(runtimeHostClientProvider),
        beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
      );
      final pipeline = PromptWorkspacePipeline(
        generateIdentity: runtime.generateIdentity,
        checkBranchExists: (project, branchName) {
          return ref
              .read(gitBackendProvider)
              .branchExists(project.repoPath, branchName);
        },
        workspaceBranches: (project) {
          return ref
              .read(workbenchControllerProvider)
              .workspacesFor(project.id)
              .where((workspace) => workspace.isActive)
              .map((workspace) => workspace.branch?.trim() ?? '')
              .where((branch) => branch.isNotEmpty)
              .toSet();
        },
        createWorkspace: controller.createWorkspaceForPrompt,
        launchAgent: runtime.launchAgent,
        onPhase: (phase) => _setPhase(id, phase),
      );
      try {
        final result = await pipeline.run(requestToRun);
        var setupStarted = requestToRun.setupStarted;
        _upsert(
          BackgroundSetupJob(
            id: id,
            kind: .promptWorkspace,
            status: .running,
            title: 'Starting agent',
            phase: 'Starting agent',
            snapshot: requestToRun.withCreated(
              result.creation,
              clientMutationId: result.clientMutationId,
              originalLaunchWasIdempotent: result.originalLaunchWasIdempotent,
              setupStarted: setupStarted,
            ),
          ),
        );
        await controller.completePromptWorkspaceCreation(
          creation: result.creation,
          agentTabId: result.agentTabId,
          openDeferredSetup: !setupStarted,
        );
        if (!setupStarted) {
          setupStarted = true;
          _upsert(
            BackgroundSetupJob(
              id: id,
              kind: .promptWorkspace,
              status: .running,
              title: 'Starting agent',
              snapshot: requestToRun.withCreated(
                result.creation,
                clientMutationId: result.clientMutationId,
                originalLaunchWasIdempotent: result.originalLaunchWasIdempotent,
                setupStarted: true,
              ),
            ),
          );
        }
        _publishWorkspaceCreated(result.creation);
      } on PromptWorkspaceLaunchException catch (failure) {
        var setupStarted = requestToRun.setupStarted;
        _upsert(
          BackgroundSetupJob(
            id: id,
            kind: .promptWorkspace,
            status: .running,
            title: 'Starting agent',
            phase: 'Starting agent',
            snapshot: requestToRun.withCreated(
              failure.creation,
              clientMutationId: failure.clientMutationId,
              originalLaunchWasIdempotent: failure.originalLaunchWasIdempotent,
              setupStarted: setupStarted,
            ),
          ),
        );
        try {
          await controller.completePromptWorkspaceCreation(
            creation: failure.creation,
            openDeferredSetup: !setupStarted,
          );
          setupStarted = true;
          _upsert(
            BackgroundSetupJob(
              id: id,
              kind: .promptWorkspace,
              status: .running,
              title: 'Starting agent',
              snapshot: requestToRun.withCreated(
                failure.creation,
                clientMutationId: failure.clientMutationId,
                originalLaunchWasIdempotent:
                    failure.originalLaunchWasIdempotent,
                setupStarted: true,
              ),
            ),
          );
        } catch (_) {}
        rethrow;
      }
    }).whenComplete(() {
      _inFlightIds.remove(id);
    });
  }
}
