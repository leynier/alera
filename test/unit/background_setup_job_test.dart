import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_clone_job.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime host events include project clone job updates', () {
    expect(runtimeHostEventNames, contains('projectCloneJobsChanged'));
  });

  test('failed jobs stay retryable until dismissed', () {
    final now = DateTime.utc(2026, 9, 10);
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo',
      createdAt: now,
      updatedAt: now,
    );
    final snapshot = ManualWorkspaceCreateRequest(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feat/one',
      reuseExistingBranch: false,
    );
    var state = const BackgroundSetupJobsState();
    state = state.withJob(
      BackgroundSetupJob(
        id: 'job-1',
        kind: .manualWorkspace,
        status: .failed,
        title: 'Creating workspace "feat/one"',
        snapshot: snapshot,
        error: 'The branch already exists.',
      ),
    );

    expect(state.jobById('job-1')?.canRetry, isTrue);
    state = state.withoutJob('job-1');
    expect(state.jobs, isEmpty);
  });

  test('retry lock hides failed jobs and keeps running jobs visible', () {
    final now = DateTime.utc(2026, 9, 10);
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo',
      createdAt: now,
      updatedAt: now,
    );
    final snapshot = ManualWorkspaceCreateRequest(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feat/one',
      reuseExistingBranch: false,
    );
    var state = BackgroundSetupJobsState(
      formLockCount: 1,
      jobs: <BackgroundSetupJob>[
        BackgroundSetupJob(
          id: 'job-failed',
          kind: .manualWorkspace,
          status: .failed,
          title: 'Creating workspace "feat/one"',
          snapshot: snapshot,
          error: 'The branch already exists.',
        ),
        BackgroundSetupJob(
          id: 'job-running',
          kind: .manualWorkspace,
          status: .running,
          title: 'Creating workspace "feat/two"',
          snapshot: snapshot,
        ),
      ],
    );

    expect(state.retryLocked, isTrue);
    expect(state.visible, hasLength(1));
    expect(state.visible.single.id, 'job-running');
    state = state.withFormLockCount(0);
    expect(state.retryLocked, isFalse);
    expect(state.visible, hasLength(2));
  });

  test('clone request snapshot matches destination for pending cards', () {
    const pending = ProjectCloneRequest(
      gitUrl: 'https://example.com/repo.git',
      destinationPath: '/projects/alera',
      name: 'alera',
    );
    expect(pending.destinationPath, '/projects/alera');
    expect(pending.displayName, 'alera');
  });

  test('clone job json keeps the submitted project name', () {
    final job = ProjectCloneJob.fromJson(<String, Object?>{
      'id': 'clone-1',
      'source': 'https://example.com/repo.git',
      'destinationPath': '/projects/alera',
      'status': 'failed',
      'phase': 'cloning',
      'projectName': 'Alera',
      'updatedAt': '2026-09-10T12:00:00Z',
    });
    expect(job.projectName, 'Alera');
  });

  test('manual and clone snapshots prefer a trimmed name', () {
    final project = _project();
    expect(
      ManualWorkspaceCreateRequest(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feat/one',
        reuseExistingBranch: false,
        name: '  Featured  ',
      ).displayName,
      'Featured',
    );
    expect(
      ManualWorkspaceCreateRequest(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feat/one',
        reuseExistingBranch: false,
        name: '   ',
      ).displayName,
      'feat/one',
    );
    expect(
      const ProjectCloneRequest(
        gitUrl: 'https://example.com/repo.git',
        destinationPath: '/projects/alera',
      ).displayName,
      '/projects/alera',
    );
  });

  test('prompt launch snapshots copy created metadata and compare targets', () {
    final project = _project();
    final otherProject = _project(id: 'project-2');
    final created = _creation(project.id);
    final request = PromptWorkspaceCreateRequest(
      project: _project(),
      prompt: '  ship it  ',
      profileId: 'codex',
      sourceBranch: 'main',
      parentWorkspaceId: 'parent-1',
      hostId: 'local',
      clientMutationId: 'mut-1',
      originalLaunchWasIdempotent: true,
      setupStarted: false,
    );
    final copied = request.withCreated(
      created,
      clientMutationId: 'mut-2',
      originalLaunchWasIdempotent: false,
      setupStarted: true,
    );
    expect(copied.created, created);
    expect(copied.clientMutationId, 'mut-2');
    expect(copied.originalLaunchWasIdempotent, isFalse);
    expect(copied.setupStarted, isTrue);
    expect(copied.parentWorkspaceId, 'parent-1');
    expect(request.withCreated(created).clientMutationId, 'mut-1');
    expect(
      request.matchesLaunchTarget(
        PromptWorkspaceCreateRequest(
          project: project,
          prompt: 'ship it',
          profileId: 'codex',
          sourceBranch: 'main',
          hostId: 'local',
        ),
      ),
      isTrue,
    );
    expect(
      request.matchesLaunchTarget(
        PromptWorkspaceCreateRequest(
          project: otherProject,
          prompt: 'ship it',
          profileId: 'codex',
          sourceBranch: 'main',
          hostId: 'local',
        ),
      ),
      isFalse,
    );
  });

  test('job copy and state helpers replace, hide, and clamp', () {
    final snapshot = ManualWorkspaceCreateRequest(
      project: _project(),
      sourceBranch: 'main',
      newBranchName: 'feat/one',
      reuseExistingBranch: false,
    );
    final running = BackgroundSetupJob(
      id: 'job-1',
      kind: .manualWorkspace,
      status: .running,
      title: 'Creating workspace "feat/one"',
      snapshot: snapshot,
      phase: 'Creating workspace',
      error: 'stale',
      progressPercent: 10,
      runtimeJobId: 'runtime-1',
      canCancel: true,
    );
    expect(running.isFailed, isFalse);
    expect(running.canRetry, isFalse);

    final failed = running.copyWith(
      status: .failed,
      title: 'Failed',
      clearPhase: true,
      clearError: true,
      clearProgress: true,
      canCancel: false,
    );
    expect(failed.phase, isNull);
    expect(failed.error, isNull);
    expect(failed.progressPercent, isNull);
    expect(failed.canRetry, isTrue);
    expect(failed.runtimeJobId, 'runtime-1');

    final updated = running.copyWith(
      phase: 'Linking parent',
      error: 'boom',
      progressPercent: 40,
      runtimeJobId: 'runtime-2',
    );
    expect(updated.phase, 'Linking parent');
    expect(updated.error, 'boom');
    expect(updated.progressPercent, 40);
    expect(updated.runtimeJobId, 'runtime-2');

    var clearPhase = false;
    var clearError = false;
    var clearProgress = false;
    final preserved = running.copyWith(
      clearPhase: clearPhase,
      clearError: clearError,
      clearProgress: clearProgress,
    );
    expect(preserved.phase, 'Creating workspace');
    expect(preserved.error, 'stale');
    expect(preserved.progressPercent, 10);
    expect(preserved.canCancel, isTrue);

    var state = const BackgroundSetupJobsState()
        .withJob(running)
        .withJob(
          BackgroundSetupJob(
            id: 'job-2',
            kind: .manualWorkspace,
            status: .running,
            title: 'Creating workspace "feat/two"',
            snapshot: snapshot,
          ),
        );
    expect(state.jobById('missing'), isNull);
    expect(state.jobs, hasLength(2));
    state = state.withJob(failed);
    expect(state.jobs, hasLength(2));
    expect(state.jobById('job-1')?.status, BackgroundSetupJobStatus.failed);
    expect(state.jobById('job-2')?.id, 'job-2');
    expect(state.withFormLockCount(-2).formLockCount, 0);

    final pipeline = PromptWorkspacePipelineResult(
      creation: _creation('project-1'),
      agentTabId: 'tab-1',
      clientMutationId: 'mut-1',
      originalLaunchWasIdempotent: true,
    );
    expect(pipeline.agentTabId, 'tab-1');
    expect(pipeline.originalLaunchWasIdempotent, isTrue);
  });

  test('clone jobs parse defaults and report active statuses', () {
    final queued = ProjectCloneJob.fromJson(<String, Object?>{
      'status': 'queued',
    });
    expect(queued.id, isEmpty);
    expect(queued.source, isEmpty);
    expect(queued.destinationPath, isEmpty);
    expect(queued.status, ProjectCloneJobStatus.queued);
    expect(queued.phase, 'cloning');
    expect(queued.isActive, isTrue);
    expect(queued.updatedAt.isUtc, isTrue);

    final running = ProjectCloneJob.fromJson(<String, Object?>{
      'id': 'clone-2',
      'source': 'https://example.com/repo.git',
      'destinationPath': '/projects/alera',
      'status': 'running',
      'phase': 'checking out',
      'progressPercent': 40,
      'message': 'Fetching',
      'error': null,
      'projectId': 'project-1',
      'workspaceId': 'ws-1',
      'updatedAt': 'not-a-date',
    });
    expect(running.isActive, isTrue);
    expect(running.progressPercent, 40);
    expect(running.message, 'Fetching');
    expect(running.projectId, 'project-1');
    expect(running.workspaceId, 'ws-1');

    expect(
      ProjectCloneJob.fromJson(<String, Object?>{'status': 'mystery'}).status,
      ProjectCloneJobStatus.failed,
    );
    expect(
      ProjectCloneJob.fromJson(<String, Object?>{'status': 'completed'})
          .isActive,
      isFalse,
    );
    expect(
      ProjectCloneJob.fromJson(<String, Object?>{'status': 'cancelled'})
          .isActive,
      isFalse,
    );
  });
}

final _now = DateTime.utc(2026, 9, 10);

Project _project({String id = 'project-1'}) {
  return Project(
    id: id,
    name: 'Alera',
    repoPath: '/repo',
    createdAt: _now,
    updatedAt: _now,
  );
}

WorkspaceCreationResult _creation(String projectId) {
  return WorkspaceCreationResult(
    workspace: Workspace(
      id: 'ws-1',
      projectId: projectId,
      name: 'feat/one',
      path: '/repo/ws-1',
      createdAt: _now,
      updatedAt: _now,
      kind: .linked,
      status: .active,
    ),
    setupReport: .empty,
  );
}
