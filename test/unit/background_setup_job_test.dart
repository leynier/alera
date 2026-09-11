import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_clone_job.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
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
}
