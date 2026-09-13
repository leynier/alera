import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';

enum BackgroundSetupJobStatus { running, failed }

enum BackgroundSetupJobKind { manualWorkspace, promptWorkspace }

class const ManualWorkspaceCreateRequest({
  required final String hostId,
  required final String projectId,
  required final String branch,
  final String? sourceBranch,
  final bool reuseExistingBranch = false,
  final String? name,
  final String? parentWorkspaceId,
  final String? issueUrl,
}) {
  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return branch;
  }
}

class const PromptWorkspaceCreateRequest({
  required final String hostId,
  required final String prompt,
  required final String projectId,
  required final String sourceBranch,
  required final String profileId,
  required final Set<String> workspaceBranches,
  final String? parentWorkspaceId,
  final String? issueUrl,
  final WorkspaceCreationResult? created,
  final String? clientMutationId,
  final bool? originalLaunchWasIdempotent,
  final bool setupStarted = false,
}) {
  PromptWorkspaceCreateRequest withCreated(
    WorkspaceCreationResult created, {
    String? clientMutationId,
    bool? originalLaunchWasIdempotent,
    bool? setupStarted,
  }) {
    return PromptWorkspaceCreateRequest(
      hostId: hostId,
      prompt: prompt,
      projectId: projectId,
      sourceBranch: sourceBranch,
      profileId: profileId,
      workspaceBranches: workspaceBranches,
      parentWorkspaceId: parentWorkspaceId,
      issueUrl: issueUrl,
      created: created,
      clientMutationId: clientMutationId ?? this.clientMutationId,
      originalLaunchWasIdempotent:
          originalLaunchWasIdempotent ?? this.originalLaunchWasIdempotent,
      setupStarted: setupStarted ?? this.setupStarted,
    );
  }

  bool matchesLaunchTarget(PromptWorkspaceCreateRequest other) {
    return projectId == other.projectId &&
        sourceBranch == other.sourceBranch &&
        hostId == other.hostId &&
        profileId == other.profileId &&
        prompt.trim() == other.prompt.trim();
  }
}

class const BackgroundSetupJob({
  required final String id,
  required final BackgroundSetupJobKind kind,
  required final BackgroundSetupJobStatus status,
  required final String title,
  required final Object snapshot,
  final String? phase,
  final String? error,
}) {
  bool get isFailed => status == BackgroundSetupJobStatus.failed;

  bool get canRetry => isFailed;
}

class const BackgroundSetupJobsState({
  final List<BackgroundSetupJob> jobs = const <BackgroundSetupJob>[],
  final int formLockCount = 0,
}) {
  bool get retryLocked => formLockCount > 0;
  BackgroundSetupJob? jobById(String id) {
    for (final job in jobs) {
      if (job.id == id) {
        return job;
      }
    }
    return null;
  }

  BackgroundSetupJobsState withJob(BackgroundSetupJob job) {
    final next = <BackgroundSetupJob>[
      for (final candidate in jobs)
        if (candidate.id == job.id) job else candidate,
    ];
    if (next.every((candidate) => candidate.id != job.id)) {
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
