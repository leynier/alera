import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';

enum BackgroundSetupJobStatus { running, failed }

enum BackgroundSetupJobKind { manualWorkspace, promptWorkspace, projectClone }

sealed class const BackgroundSetupRetrySnapshot();

class const ManualWorkspaceCreateRequest({
  required final Project project,
  required final String sourceBranch,
  required final String newBranchName,
  required final bool reuseExistingBranch,
  final String? name,
  final String? parentWorkspaceId,
  final String? hostId,
}) extends BackgroundSetupRetrySnapshot {
  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return newBranchName;
  }
}

class const PromptWorkspaceCreateRequest({
  required final Project project,
  required final String prompt,
  required final String profileId,
  required final String sourceBranch,
  final String? parentWorkspaceId,
  final String? hostId,
  final WorkspaceCreationResult? created,
  final String? clientMutationId,
  final bool? originalLaunchWasIdempotent,
  final bool setupStarted = false,
}) extends BackgroundSetupRetrySnapshot {
  PromptWorkspaceCreateRequest withCreated(
    WorkspaceCreationResult created, {
    String? clientMutationId,
    bool? originalLaunchWasIdempotent,
    bool? setupStarted,
  }) {
    return PromptWorkspaceCreateRequest(
      project: project,
      prompt: prompt,
      profileId: profileId,
      sourceBranch: sourceBranch,
      parentWorkspaceId: parentWorkspaceId,
      hostId: hostId,
      created: created,
      clientMutationId: clientMutationId ?? this.clientMutationId,
      originalLaunchWasIdempotent:
          originalLaunchWasIdempotent ?? this.originalLaunchWasIdempotent,
      setupStarted: setupStarted ?? this.setupStarted,
    );
  }

  bool matchesLaunchTarget(PromptWorkspaceCreateRequest other) {
    return project.id == other.project.id &&
        sourceBranch == other.sourceBranch &&
        hostId == other.hostId &&
        profileId == other.profileId &&
        prompt.trim() == other.prompt.trim();
  }
}

class const ProjectCloneRequest({
  required final String gitUrl,
  required final String destinationPath,
  final String? name,
}) extends BackgroundSetupRetrySnapshot {
  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return destinationPath;
  }
}

class const BackgroundSetupJob({
  required final String id,
  required final BackgroundSetupJobKind kind,
  required final BackgroundSetupJobStatus status,
  required final String title,
  required final BackgroundSetupRetrySnapshot snapshot,
  final String? phase,
  final String? error,
  final int? progressPercent,
  final String? runtimeJobId,
  final bool canCancel = false,
}) {
  bool get isFailed => status == BackgroundSetupJobStatus.failed;

  bool get canRetry => isFailed;

  BackgroundSetupJob copyWith({
    BackgroundSetupJobStatus? status,
    String? title,
    String? phase,
    String? error,
    int? progressPercent,
    String? runtimeJobId,
    bool? canCancel,
    bool clearPhase = false,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return BackgroundSetupJob(
      id: id,
      kind: kind,
      status: status ?? this.status,
      title: title ?? this.title,
      snapshot: snapshot,
      phase: clearPhase ? null : (phase ?? this.phase),
      error: clearError ? null : (error ?? this.error),
      progressPercent: clearProgress
          ? null
          : (progressPercent ?? this.progressPercent),
      runtimeJobId: runtimeJobId ?? this.runtimeJobId,
      canCancel: canCancel ?? this.canCancel,
    );
  }
}

class const BackgroundSetupJobsState({
  final List<BackgroundSetupJob> jobs = const <BackgroundSetupJob>[],
  final int formLockCount = 0,
}) {
  bool get retryLocked => formLockCount > 0;

  List<BackgroundSetupJob> get visible {
    if (!retryLocked) {
      return jobs;
    }
    return List.unmodifiableOf(<BackgroundSetupJob>[
      for (final job in jobs)
        if (!job.isFailed) job,
    ]);
  }

  BackgroundSetupJob? jobById(String id) {
    for (final job in jobs) {
      if (job.id == id) {
        return job;
      }
    }
    return null;
  }

  BackgroundSetupJobsState withJob(BackgroundSetupJob job) {
    final next = <BackgroundSetupJob>[];
    var replaced = false;
    for (final candidate in jobs) {
      if (candidate.id == job.id) {
        next.add(job);
        replaced = true;
      } else {
        next.add(candidate);
      }
    }
    if (!replaced) {
      next.add(job);
    }
    return BackgroundSetupJobsState(
      jobs: List.unmodifiableOf(next),
      formLockCount: formLockCount,
    );
  }

  BackgroundSetupJobsState withoutJob(String id) {
    return BackgroundSetupJobsState(
      jobs: List.unmodifiableOf(<BackgroundSetupJob>[
        for (final job in jobs)
          if (job.id != id) job,
      ]),
      formLockCount: formLockCount,
    );
  }

  BackgroundSetupJobsState withFormLockCount(int count) {
    return BackgroundSetupJobsState(
      jobs: jobs,
      formLockCount: count < 0 ? 0 : count,
    );
  }
}

class const PromptWorkspacePipelineResult({
  required final WorkspaceCreationResult creation,
  required final String agentTabId,
  final String? clientMutationId,
  final bool? originalLaunchWasIdempotent,
});
