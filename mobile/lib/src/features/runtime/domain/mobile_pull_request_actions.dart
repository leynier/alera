import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

/// Merge methods a phone can offer, with the runtime's wire names and the
/// desktop's labels (`review_merge_method.dart`).
enum MobilePullRequestMergeMethod(final String wireName, final String label) {
  mergeCommit('mergeCommit', 'Create Merge Commit'),
  squash('squash', 'Squash and Merge'),
  rebase('rebase', 'Rebase and Merge');

  static MobilePullRequestMergeMethod? fromWireName(String value) {
    for (final method in values) {
      if (method.wireName == value) {
        return method;
      }
    }
    return null;
  }
}

/// The pull request write in flight for one workspace.
enum PullRequestActionKind {
  comment,
  editComment,
  merge,
  draftStatus,
  close,
  link,
  unlink,
  create,
}

/// What the phone asks the runtime to create.
typedef MobilePullRequestCreateInput = ({
  String baseBranch,
  String title,
  String body,
  bool draft,
});

/// Pull request writes the paired runtime runs through `gh`. Every write
/// answers with the fresh snapshot, so the panel shows what changed without a
/// second request.
abstract interface class MobilePullRequestActionsClient {
  bool get supportsPullRequestActions;

  Future<MobilePullRequestSnapshot> commentOnPullRequest({
    required String workspaceId,
    required int number,
    required String body,
    int? replyToCommentId,
  });

  Future<MobilePullRequestSnapshot> editPullRequestComment({
    required String workspaceId,
    required int number,
    required MobilePullRequestComment comment,
    required String body,
  });

  Future<MobilePullRequestSnapshot> mergePullRequest({
    required String workspaceId,
    required int number,
    required MobilePullRequestMergeMethod method,
  });

  Future<MobilePullRequestSnapshot> setPullRequestDraft({
    required String workspaceId,
    required int number,
    required bool draft,
  });

  Future<MobilePullRequestSnapshot> closePullRequest({
    required String workspaceId,
    required int number,
  });

  Future<MobilePullRequestSnapshot> linkPullRequest({
    required String workspaceId,
    required String reference,
  });

  Future<MobilePullRequestSnapshot> unlinkPullRequest({
    required String workspaceId,
    required int number,
    String? url,
  });

  Future<MobilePullRequestSnapshot> createPullRequest({
    required String workspaceId,
    required MobilePullRequestCreateInput input,
  });

  /// Whether AI Assist on the runtime can write a pull request title and
  /// description (`aiTextPullRequestDetailsV1`).
  bool get supportsPullRequestDetailsGeneration;

  /// A title and description for the range between [baseBranch] and HEAD.
  Future<MobilePullRequestDetails> generatePullRequestDetails({
    required String workspaceId,
    required String baseBranch,
  });
}

/// A generated pull request title and description.
typedef MobilePullRequestDetails = ({String title, String body});

enum MobilePullRequestReviewActionKind {
  markReady,
  merge,
  convertToDraft,
  close,
  unlink,
}

/// One entry of the review action menu. [method] is set only for merges.
final class const MobilePullRequestReviewAction({
  required final MobilePullRequestReviewActionKind kind,
  final MobilePullRequestMergeMethod? method,
}) {
  String get label => switch (kind) {
    .markReady => 'Mark Ready For Review',
    .merge => method!.label,
    .convertToDraft => 'Convert To Draft',
    .close => 'Close Pull Request',
    .unlink => 'Unlink Pull Request',
  };

  bool get destructive => kind == .close;

  @override
  bool operator ==(Object other) =>
      other is MobilePullRequestReviewAction &&
      other.kind == kind &&
      other.method == method;

  @override
  int get hashCode => Object.hash(kind, method);
}

/// GitHub reports a draft as `OPEN` plus `isDraft`.
bool _isOpen(MobilePullRequestReview review) =>
    review.state.toUpperCase() == 'OPEN';

/// The desktop's action set (`_PullRequestReviewActions`), in its order: ready
/// first for a draft, then the allowed merge methods, draft conversion, close,
/// and unlink, which is always available.
List<MobilePullRequestReviewAction> availablePullRequestReviewActions(
  MobilePullRequestSnapshot snapshot,
) {
  final review = snapshot.review;
  if (review == null) {
    return const <MobilePullRequestReviewAction>[];
  }
  final open = _isOpen(review);
  return <MobilePullRequestReviewAction>[
    if (open && review.isDraft)
      const MobilePullRequestReviewAction(kind: .markReady),
    if (open)
      for (final name in snapshot.mergeMethods)
        if (MobilePullRequestMergeMethod.fromWireName(name) case final method?)
          MobilePullRequestReviewAction(kind: .merge, method: method),
    if (open && !review.isDraft)
      const MobilePullRequestReviewAction(kind: .convertToDraft),
    if (open) const MobilePullRequestReviewAction(kind: .close),
    const MobilePullRequestReviewAction(kind: .unlink),
  ];
}

/// A draft or a conflicting pull request lists its merge methods but cannot
/// run them, like the desktop button.
bool pullRequestReviewActionEnabled(
  MobilePullRequestReviewAction action,
  MobilePullRequestReview review,
) {
  return switch (action.kind) {
    .merge =>
      _isOpen(review) &&
          !review.isDraft &&
          review.mergeable?.toUpperCase() != 'CONFLICTING',
    _ => true,
  };
}

/// Copy for the confirmation shown before an action, matching the desktop
/// dialogs.
typedef MobilePullRequestActionConfirmation = ({
  String title,
  String message,
  String confirmLabel,
  bool destructive,
});

MobilePullRequestActionConfirmation pullRequestActionConfirmation(
  MobilePullRequestReviewAction action,
  int number,
) {
  return switch (action.kind) {
    .merge => (
      title: '${action.label} PR #$number?',
      message: 'This will update the pull request on GitHub.',
      confirmLabel: action.label,
      destructive: false,
    ),
    .close => (
      title: 'Close Pull Request #$number?',
      message: 'This will close the pull request without merging it.',
      confirmLabel: 'Close Pull Request',
      destructive: true,
    ),
    .unlink => (
      title: 'Unlink Pull Request #$number?',
      message: 'This will remove the pull request link from this workspace. The pull request on GitHub will not be changed.',
      confirmLabel: 'Unlink Pull Request',
      destructive: false,
    ),
    .markReady => (
      title: 'Mark Ready For Review PR #$number?',
      message: 'This will mark the pull request as ready for review on GitHub.',
      confirmLabel: 'Mark Ready For Review',
      destructive: false,
    ),
    .convertToDraft => (
      title: 'Convert To Draft PR #$number?',
      message: 'This will convert the pull request to draft on GitHub.',
      confirmLabel: 'Convert To Draft',
      destructive: false,
    ),
  };
}

/// The sentence a failed write shows. The runtime already words its errors
/// for people, so only transport failures need translating.
String pullRequestActionErrorMessage(Object error) {
  return switch (error) {
    StateError(:final message) => message,
    UnsupportedError(:final message?) => message,
    TimeoutException() => 'The paired computer did not answer in time.',
    _ => error.toString(),
  };
}
