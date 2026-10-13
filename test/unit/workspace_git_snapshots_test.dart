import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/workbench/application/workspace_details_provider.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_comparison_loader.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';
import 'fake_source_control_watcher.dart';

class _Workbench extends WorkbenchController {
  @override
  WorkbenchState build() => const WorkbenchState();
}

class _Reviews extends WorkspacePullRequestController {
  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async => const WorkspacePullRequestState();
  void setRefreshing(bool value) {
    state = AsyncData(
      state.requireValue.copyWith(
        action: value ? PullRequestAction.refresh : null,
        clearAction: !value,
      ),
    );
  }
}

class _Git extends FakeGitBackend {
  int comparisons = 0;
  @override
  Future<GitWorkspaceComparison> workspaceComparison(
    String path, {
    String? baseRef,
  }) {
    comparisons++;
    return super.workspaceComparison(path, baseRef: baseRef);
  }
}

const _scope = WorkspacePullRequestScope(
  workspaceId: 'w',
  repoPath: '/repo',
  branch: 'feature',
  sourceBranch: 'main',
);

void main() {
  test('PR activity and busy states reuse comparisons; file edits reuse the catalog', () async {
    final git = _Git()..sourceBranches = ['main', 'feature'];
    final watcher = FakeSourceControlWatcher();
    addTearDown(watcher.dispose);
    final reviews = _Reviews();
    final container = ProviderContainer(
      overrides: [
        gitBackendProvider.overrideWithValue(git),
        sourceControlWatcherProvider.overrideWithValue(watcher),
        workbenchControllerProvider.overrideWith(_Workbench.new),
        workspacePullRequestControllerProvider(_scope)
            .overrideWith(() => reviews),
      ],
    );
    addTearDown(container.dispose);
    final provider = workspaceDetailsProvider(_scope);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final source = container.read(
      workspaceSourceControlControllerProvider('/repo').notifier,
    );
    source.attachView();
    await Future.pause(const Duration(milliseconds: 350));
    await container.read(provider.future);
    final initialComparisons = git.comparisons;
    final initialCatalogs = git.calls
        .where((call) => call.method == 'listBranches')
        .length;
    reviews.setRefreshing(true);
    await container.read(provider.future);
    reviews.setRefreshing(false);
    await container.read(provider.future);
    expect(git.comparisons, initialComparisons);
    expect(
      git.calls.where((call) => call.method == 'listBranches').length,
      initialCatalogs,
    );
    watcher.emitChange(repository: false, catalog: false);
    await Future.pause(const Duration(milliseconds: 350));
    await container.read(provider.future);
    expect(git.comparisons, initialComparisons + 1);
    expect(
      git.calls.where((call) => call.method == 'listBranches').length,
      initialCatalogs,
    );
    await source.stage('a.dart');
    await container.read(provider.future);
    expect(git.comparisons, initialComparisons + 2);
    expect(
      git.calls.where((call) => call.method == 'listBranches').length,
      initialCatalogs,
    );
    watcher.emitChange();
    await Future.pause(const Duration(milliseconds: 350));
    await container.read(provider.future);
    expect(git.comparisons, initialComparisons + 3);
    expect(
      git.calls.where((call) => call.method == 'listBranches').length,
      initialCatalogs + 1,
    );
  });

  test(
    'slow comparison keeps one job and merges all trailing revisions',
    () async {
      final git = _Git();
      final first = Completer<GitWorkspaceComparison>();
      var loads = 0;
      final loader = WorkspaceComparisonLoader(
        loadSnapshot: () {
          loads++;
          return loads == 1 ? first.future : git.workspaceComparison('/repo');
        },
      );
      final original = loader.load(1);
      final pending = [for (var i = 2; i <= 20; i++) loader.load(i)];
      expect(loads, 1);
      first.complete(await git.workspaceComparison('/repo'));
      await Future.wait([original, ...pending]);
      expect(loads, 2);
      await loader.load(20);
      expect(loads, 2);
      loader.dispose();
    },
  );
}
