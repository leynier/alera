import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';

enum WorkspaceReviewAction {
  resolve('Resolve'),
  ready('Ready'),
  fix('Fix'),
  merge('Merge');

  WorkspaceReviewAction(this.label);
  final String label;
}

class const WorkspaceReviewActionState({this.action, this.hint}) {
  final WorkspaceReviewAction? action;
  final String? hint;
}

WorkspaceReviewActionState resolveWorkspaceReviewAction(
  WorkspacePullRequestState state,
) {
  final review = state.review;
  if (review == null || !review.isOpen) {
    return const WorkspaceReviewActionState();
  }
  if (state.isBusy && !state.isRefreshing) {
    return const WorkspaceReviewActionState(
      hint: 'Another pull request action is running.',
    );
  }
  if (!state.isAuthenticated) {
    return const WorkspaceReviewActionState(
      hint: 'Sign in to the hosting provider.',
    );
  }
  if (review.mergeable == HostedReviewMergeable.conflicting) {
    return const WorkspaceReviewActionState(action: .resolve);
  }
  if (review.state == HostedReviewState.draft) {
    return state.canChangeDraftStatus && state.actionAccess.canMarkReady == true
        ? const WorkspaceReviewActionState(action: .ready)
        : const WorkspaceReviewActionState(
            hint: 'Marking this PR ready is unavailable for this account.',
          );
  }
  if (!state.checksLoaded || state.checksErrorMessage != null) {
    return const WorkspaceReviewActionState(
      hint: 'Checks are unavailable. Refresh before merging.',
    );
  }
  if (state.checksRollup == ReviewChecksRollup.failure) {
    return const WorkspaceReviewActionState(action: .fix);
  }
  if (state.checksRollup == ReviewChecksRollup.pending) {
    return const WorkspaceReviewActionState(hint: 'Checks are still running.');
  }
  if (review.mergeable != HostedReviewMergeable.mergeable) {
    return const WorkspaceReviewActionState(
      hint: 'Mergeability has not been confirmed.',
    );
  }
  if (state.actionAccess.canMerge != true ||
      state.mergeMethods.isEmpty ||
      state.mergeMethodsErrorMessage != null) {
    return const WorkspaceReviewActionState(
      hint: 'No permitted merge method is available for this account.',
    );
  }
  if (state.stackErrorMessage != null) {
    return WorkspaceReviewActionState(hint: state.stackErrorMessage);
  }
  if (state.stack != null &&
      (!state.stackChecksLoaded || state.stackMergeBlocker != null)) {
    return WorkspaceReviewActionState(
      hint: state.stackMergeBlocker ?? 'Stack checks are unavailable.',
    );
  }
  return const WorkspaceReviewActionState(action: .merge);
}

String reviewActionFingerprint(WorkspacePullRequestState state) {
  String key(HostedReview review) =>
      '${review.provider.name}:${review.number}:${review.state.name}:${review.headSha}:${review.baseBranch}:${review.headBranch}';
  final identity = state.identity;
  return '${identity?.host}:${identity?.owner}:${identity?.project}:${identity?.repo}|${state.review == null ? '' : key(state.review!)}|${state.stack?.entriesThrough(state.review?.number ?? -1).map((entry) => key(entry.review)).join('|') ?? ''}';
}
