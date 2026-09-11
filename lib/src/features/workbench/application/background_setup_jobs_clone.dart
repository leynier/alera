part of 'background_setup_jobs.dart';

mixin _BackgroundSetupJobsInternals on _$BackgroundSetupJobs {
  bool _disposed = false;
  StreamSubscription<RuntimeHostEvent>? _runtimeEvents;
  final Set<String> _dismissedCloneIds = <String>{};
  final Set<String> _inFlightIds = <String>{};
  Future<void> _refreshChain = Future<void>.value();

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

mixin _BackgroundSetupJobsClone
    on _$BackgroundSetupJobs, _BackgroundSetupJobsInternals {
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
}
