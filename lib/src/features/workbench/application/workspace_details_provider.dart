import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/features/workbench/domain/workspace_comparison_base.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_details_provider.g.dart';

class const WorkspaceDetailsState({
  required this.sourceControl,
  required this.comparison,
  required this.branches,
  required this.defaultBranch,
  required this.quickAction,
  required this.pullRequest,
  required this.hasRemote,
  this.remoteNames = const [],
}) {
  final bool hasRemote;
  final List<String> remoteNames;
  final WorkspaceSourceControlState sourceControl;
  final GitWorkspaceComparison comparison;
  final List<String> branches;
  final String defaultBranch;
  final WorkspaceGitQuickActionState quickAction;
  final WorkspacePullRequestState? pullRequest;
}

@riverpod
Future<WorkspaceDetailsState> workspaceDetails(
  Ref ref,
  WorkspacePullRequestScope scope,
) async {
  final sourceFuture = ref.watch(
    workspaceSourceControlControllerProvider(scope.repoPath).future,
  );
  final reviewProvider = workspacePullRequestControllerProvider(scope);
  ref.watch(
    reviewProvider.select(
      (value) => (
        value.value?.review?.baseBranch,
        value.value?.review?.isOpen,
        value.value?.supportsCreation,
        value.value?.isBusy,
        value.value?.identity?.provider,
      ),
    ),
  );
  final pullRequest = ref.read(reviewProvider).value;
  final explicitBase = ref.watch(
    workbenchControllerProvider.select(
      (state) => state
          .viewPrefs
          .workspaceComparisonBases['${scope.workspaceId}:${scope.repoPath}'],
    ),
  );
  final git = ref.read(gitBackendProvider);
  final source = await sourceFuture;
  final branches = await git.listBranches(scope.repoPath);
  final defaultBranch = await git.workspaceDefaultBranch(scope.repoPath);
  final remotes = await git.listRemotes(scope.repoPath);
  final resolvedBase = resolveWorkspaceComparisonBase(
    branches: branches,
    defaultBranch: defaultBranch,
    explicitBase: explicitBase,
    openReviewBase: pullRequest?.review?.isOpen == true
        ? pullRequest?.review?.baseBranch
        : null,
    sourceBranch: scope.sourceBranch,
    remoteNames: remotes.map((remote) => remote.name).toList(growable: false),
  );
  final comparison = await git.workspaceComparison(
    scope.repoPath,
    baseRef: resolvedBase,
  );
  final current = source.repositoryState;
  final defaultShort = defaultBranch.startsWith('origin/')
      ? defaultBranch.substring(7)
      : defaultBranch;
  return WorkspaceDetailsState(
    sourceControl: source,
    comparison: comparison,
    branches: branches,
    defaultBranch: defaultShort,
    pullRequest: pullRequest,
    hasRemote: remotes.isNotEmpty,
    remoteNames: remotes.map((remote) => remote.name).toList(growable: false),
    quickAction: resolveWorkspaceGitQuickAction(
      repository: current,
      hasChanges: source.hasChanges,
      hasRemote: remotes.isNotEmpty,
      hasOpenPr: pullRequest?.review?.isOpen == true,
      canCreatePr: pullRequest?.supportsCreation == true,
      isDefaultBranch: current.branch == defaultShort,
      hasBranchChanges: comparison.entries.isNotEmpty,
      busy: source.isBusy || (pullRequest?.isBusy ?? false),
    ),
  );
}
