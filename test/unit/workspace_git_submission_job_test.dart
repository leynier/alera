import 'dart:async';

import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission_job.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

final original = Workspace(
  id: 'original',
  projectId: 'p',
  name: 'Original',
  path: '/original',
  branch: 'main',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: .linked,
  status: .active,
);
const scope = WorkspacePullRequestScope(
  workspaceId: 'original',
  repoPath: '/original',
);
const sourceState = WorkspaceSourceControlState(
  status: GitStatusResult(entries: []),
  repositoryState: GitRepositoryState(branch: 'main'),
  stashes: [],
);

class _Workbench extends WorkbenchController {
  @override
  WorkbenchState build() => WorkbenchState(
    activeWorkspaceId: 'original',
    workspacesByProject: {
      'p': [original],
    },
  );
  void navigate() => state = state.copyWith(activeWorkspaceId: 'other');
  void removeOwner() => state = state.copyWith(workspacesByProject: {});
}

class _Source extends WorkspaceSourceControlController {
  @override
  Future<WorkspaceSourceControlState> build(String workspacePath) async =>
      sourceState;
  @override
  Future<void> runReviewedAction(Future<void> Function(GitBackend) operation) =>
      operation(ref.read(gitBackendProvider));
}

class _Reviews extends WorkspacePullRequestController {
  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async => const WorkspacePullRequestState();
}

class _Git extends FakeGitBackend {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<String> commitSelected(
    String path,
    GitWorkspaceComparison snapshot,
    List<String> files,
    String message,
  ) async {
    expect(path, '/original');
    started.complete();
    await finish.future;
    return super.commitSelected(path, snapshot, files, message);
  }
}

void main() {
  ProviderContainer container(_Git git) => ProviderContainer(
    overrides: [
      workbenchControllerProvider.overrideWith(_Workbench.new),
      gitBackendProvider.overrideWithValue(git),
      workspaceSourceControlControllerProvider('/original')
          .overrideWith(_Source.new),
      workspacePullRequestControllerProvider(scope).overrideWith(_Reviews.new),
    ],
  );
  Future<WorkspaceGitSubmission> submission(_Git git) async =>
      WorkspaceGitSubmission(
        path: '/original',
        snapshot: await git.workspaceComparison('/original'),
        action: .commit,
        files: ['selected'],
        message: 'reviewed',
      );
  test(
    'a confirmed job completes on its owner without selecting it again',
    () async {
      final git = _Git();
      final app = container(git);
      addTearDown(app.dispose);
      final run = runWorkspaceGitSubmissionJob(
        app,
        original,
        scope,
        await submission(git),
      );
      await git.started.future;
      (app.read(workbenchControllerProvider.notifier) as _Workbench).navigate();
      git.finish.complete();
      expect(await run, isNull);
      expect(app.read(workbenchControllerProvider).activeWorkspaceId, 'other');
      expect(git.calls.single.args['path'], '/original');
    },
  );
  test('removing the owner before starting blocks a stale job', () async {
    final git = _Git();
    final app = container(git);
    addTearDown(app.dispose);
    (app.read(workbenchControllerProvider.notifier) as _Workbench)
        .removeOwner();
    await expectLater(
      runWorkspaceGitSubmissionJob(app, original, scope, await submission(git)),
      throwsStateError,
    );
    expect(git.calls, isEmpty);
  });
}
