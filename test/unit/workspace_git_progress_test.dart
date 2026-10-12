import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/workspace_git_progress.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scope = WorkspacePullRequestScope(workspaceId: 'w', repoPath: '/repo');
  test('late output cannot overwrite a retry or a completed operation', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      workspaceGitProgressProvider(scope).notifier,
    );
    final first = notifier.start();
    notifier.finish(first, error: 'Commit created; push failed');
    final second = notifier.start();
    notifier.update(first, phase: 'Wrong', output: 'late');
    notifier.update(second, phase: 'Pushing', output: 'Writing objects: 50%');
    expect(
      container.read(workspaceGitProgressProvider(scope))!.phase,
      'Pushing',
    );
    notifier.finish(second);
    notifier.update(second, output: 'late');
    expect(
      container.read(workspaceGitProgressProvider(scope))!.output,
      'Writing objects: 50%',
    );
  });
  test('success clears after ten seconds while failure stays available', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final notifier = container.read(
        workspaceGitProgressProvider(scope).notifier,
      );
      notifier.finish(notifier.start());
      async.elapse(const Duration(seconds: 9));
      expect(container.read(workspaceGitProgressProvider(scope)), isNotNull);
      async.elapse(const Duration(seconds: 1));
      expect(container.read(workspaceGitProgressProvider(scope)), isNull);
      notifier.finish(notifier.start(), error: 'Push failed');
      async.elapse(const Duration(seconds: 30));
      expect(
        container.read(workspaceGitProgressProvider(scope))!.error,
        'Push failed',
      );
      container.dispose();
    });
  });
}
