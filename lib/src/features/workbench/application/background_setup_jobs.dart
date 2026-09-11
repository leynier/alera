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

@Riverpod(keepAlive: true)
class BackgroundSetupJobs extends _$BackgroundSetupJobs {
  bool _disposed = false;
  StreamSubscription<RuntimeHostEvent>? _runtimeEvents;
  final Set<String> _dismissedCloneIds = <String>{};
  final Set<String> _inFlightIds = <String>{};
  Future<void> _refreshChain = Future<void>.value();

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
        throw failure;
      }
    }).whenComplete(() {
      _inFlightIds.remove(id);
    });
  }

  Future<void> enqueueProjectClone(
    ProjectCloneRequest request, {
    String? jobId,
  }) async {
    final claimedId = jobId ?? const Uuid().v4();
    if (!_inFlightIds.add(claimedId)) {
      return;
    }
    _upsert(
      BackgroundSetupJob(
        id: claimedId,
        kind: .projectClone,
        status: .running,
        title: 'Cloning repository',
        phase: 'Cloning repository',
        snapshot: request,
      ),
    );
    try {
      final started = await ref
          .read(workbenchControllerProvider.notifier)
          .startProjectClone(
            gitUrl: request.gitUrl,
            destinationPath: request.destinationPath,
            name: request.name,
          );
      _dismissedCloneIds.remove(started.id);
      final existing = _jobForRuntimeClone(started);
      final adoptedId = existing?.id ?? started.id;
      if (claimedId != adoptedId) {
        state = state.withoutJob(claimedId);
      }
      _upsert(
        BackgroundSetupJob(
          id: adoptedId,
          kind: .projectClone,
          status: started.isActive ? .running : .failed,
          title: 'Cloning repository',
          phase: started.message ?? 'Cloning repository',
          snapshot: request,
          error: started.error,
          progressPercent: started.progressPercent,
          runtimeJobId: started.id,
          canCancel: started.isActive,
        ),
      );
      await _refreshCloneJobs();
    } catch (error) {
      final id = jobId ?? claimedId;
      if (state.jobById(id) == null) {
        _upsert(
          BackgroundSetupJob(
            id: id,
            kind: .projectClone,
            status: .failed,
            title: 'Cloning repository',
            snapshot: request,
            error: userFacingExceptionMessage(error),
          ),
        );
      } else {
        _fail(id, error);
      }
    } finally {
      _inFlightIds.remove(claimedId);
    }
  }

  Future<void> cancel(String jobId) async {
    final job = state.jobById(jobId);
    final runtimeJobId = job?.runtimeJobId;
    if (job == null || runtimeJobId == null || !job.canCancel) {
      return;
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .cancelProjectClone(runtimeJobId);
      await _refreshCloneJobs();
    } catch (error) {
      _fail(jobId, error);
    }
  }

  Future<void> _run(String jobId, Future<void> Function() action) async {
    try {
      await action();
      if (!_disposed) {
        state = state.withoutJob(jobId);
      }
    } catch (error) {
      _fail(jobId, error);
      rethrow;
    }
  }

  void _fail(String jobId, Object error) {
    final job = state.jobById(jobId);
    if (job == null || _disposed) {
      return;
    }
    _upsert(
      job.copyWith(
        status: .failed,
        error: userFacingExceptionMessage(error),
        clearPhase: true,
        canCancel: false,
      ),
    );
  }

  void _setPhase(String jobId, String phase) {
    final job = state.jobById(jobId);
    if (job == null || _disposed) {
      return;
    }
    _upsert(job.copyWith(phase: phase, title: _titleForPhase(job, phase)));
  }

  String _titleForPhase(BackgroundSetupJob job, String phase) {
    if (job.kind == .promptWorkspace && phase == 'Starting agent') {
      return 'Starting agent';
    }
    return job.title;
  }

  void _upsert(BackgroundSetupJob job) {
    if (_disposed) {
      return;
    }
    state = state.withJob(job);
  }

  void _publishWorkspaceCreated(WorkspaceCreationResult result) {
    if (result.hasSetupWarnings) {
      AleraToast.publish(
        message:
            'Workspace created with setup warnings: ${result.setupReport.summary}',
        tone: .error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (result.hasParentLinkError) {
      AleraToast.publish(
        message: 'Workspace created, but parent link failed',
        tone: .error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    AleraToast.publish(message: 'Workspace created', tone: .success);
  }

  Future<void> _refreshCloneJobs() {
    final previous = _refreshChain;
    final next = () async {
      try {
        await previous;
      } catch (_) {}
      await _refreshCloneJobsBody();
    }();
    _refreshChain = next;
    return next;
  }

  Future<void> _refreshCloneJobsBody() async {
    List<ProjectCloneJob> jobs;
    try {
      jobs = await ref
          .read(workbenchControllerProvider.notifier)
          .listProjectCloneJobs();
    } catch (_) {
      return;
    }
    if (_disposed) {
      return;
    }
    final seenRuntimeIds = <String>{};
    for (final runtimeJob in jobs) {
      seenRuntimeIds.add(runtimeJob.id);
      if (_dismissedCloneIds.contains(runtimeJob.id)) {
        continue;
      }
      final existing = _jobForRuntimeClone(runtimeJob);
      if (existing == null && !runtimeJob.isActive) {
        continue;
      }
      final snapshot =
          existing?.snapshot ??
          ProjectCloneRequest(
            gitUrl: runtimeJob.source,
            destinationPath: runtimeJob.destinationPath,
            name: runtimeJob.projectName,
          );
      if (runtimeJob.status == ProjectCloneJobStatus.completed) {
        await _completeClone(existing?.id, runtimeJob);
        continue;
      }
      if (runtimeJob.status == ProjectCloneJobStatus.cancelled) {
        if (existing != null) {
          state = state.withoutJob(existing.id);
        }
        continue;
      }
      final failed = runtimeJob.status == ProjectCloneJobStatus.failed;
      _upsert(
        BackgroundSetupJob(
          id: existing?.id ?? runtimeJob.id,
          kind: .projectClone,
          status: failed ? .failed : .running,
          title: 'Cloning repository',
          phase: runtimeJob.message ?? 'Cloning repository',
          snapshot: snapshot,
          error: runtimeJob.error,
          progressPercent: runtimeJob.progressPercent,
          runtimeJobId: runtimeJob.id,
          canCancel: runtimeJob.isActive,
        ),
      );
    }
    for (final job in List<BackgroundSetupJob>.of(state.jobs)) {
      final runtimeJobId = job.runtimeJobId;
      if (job.kind == .projectClone &&
          runtimeJobId != null &&
          !seenRuntimeIds.contains(runtimeJobId) &&
          job.status == .running) {
        _fail(job.id, StateError('Clone job disappeared.'));
      }
    }
  }

  BackgroundSetupJob? _jobForRuntimeClone(ProjectCloneJob runtimeJob) {
    for (final job in state.jobs) {
      if (job.runtimeJobId == runtimeJob.id || job.id == runtimeJob.id) {
        return job;
      }
    }
    for (final job in state.jobs) {
      if (job.kind != .projectClone || job.runtimeJobId != null) {
        continue;
      }
      final snapshot = job.snapshot;
      if (snapshot is ProjectCloneRequest &&
          snapshot.destinationPath == runtimeJob.destinationPath) {
        return job;
      }
    }
    return null;
  }

  Future<void> _completeClone(
    String? localJobId,
    ProjectCloneJob runtimeJob,
  ) async {
    final projectId = runtimeJob.projectId;
    if (projectId != null) {
      try {
        final projects = ref.read(workbenchControllerProvider).projects;
        Project? project;
        for (final candidate in projects) {
          if (candidate.id == projectId) {
            project = candidate;
            break;
          }
        }
        project ??= (await ref.read(projectRepositoryProvider).listAll())
            .where((candidate) => candidate.id == projectId)
            .firstOrNull;
        if (project != null) {
          await ref
              .read(workbenchControllerProvider.notifier)
              .activateAddedProject(project);
        }
      } catch (_) {}
    }
    if (localJobId != null) {
      state = state.withoutJob(localJobId);
    } else {
      state = state.withoutJob(runtimeJob.id);
    }
    AleraToast.publish(message: 'Project cloned', tone: .success);
  }
}
