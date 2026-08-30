import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';

/// Why the pull-request panel has no provider to work with.
enum PullRequestUnavailableReason { noRemote, undetectable, unsupported }

/// In-flight action for busy indicators.
enum PullRequestAction {
  refresh,
  link,
  unlink,
  create,
  update,
  createStack,
  linkStack,
  merge,
  mergeStack,
  close,
  draftStatus,
  comment,
}

/// Immutable state of the pull-request panel for one workspace.
class const WorkspacePullRequestState({
  final GitRemoteIdentity? identity,
  final PullRequestUnavailableReason? unavailableReason,
  final ForgeAuthStatus authStatus = ForgeAuthStatus.unknown,
  final HostedReview? review,
  this.suggestedReview,
  this.stack,
  this.stackSupported = false,
  this.stackErrorMessage,
  final List<ReviewCheck> checks = const <ReviewCheck>[],
  final List<ReviewComment> comments = const <ReviewComment>[],
  final bool linkedManually = false,
  this.dismissed = false,
  this.currentBranch,
  this.baseBranches = const <String>[],
  this.suggestedBaseBranch,
  final List<ReviewMergeMethod> mergeMethods = const <ReviewMergeMethod>[],
  final bool canCloseReview = false,
  final bool canChangeDraftStatus = false,
  final bool canComment = false,
  final bool canEditComments = false,
  final Set<String> savingCommentIds = const <String>{},
  final PullRequestAction? action,
  final String? errorMessage,
}) {
  /// Active branch review currently ignored by the workspace. The link form
  /// offers it as an explicit suggestion without displaying it automatically.
  final HostedReview? suggestedReview;

  /// GitHub-native stack containing [review], ordered bottom to top.
  final HostedReviewStack? stack;

  /// Whether the resolved forge exposes native stack operations.
  final bool stackSupported;

  /// A stack-specific load failure that does not hide the pull request itself.
  final String? stackErrorMessage;

  /// Whether the workspace currently carries a dismissal record that applies
  /// to the active branch review or no active review exists yet.
  final bool dismissed;

  /// The current branch of the controlled repository, or null when detached or
  /// unavailable. Drives auto-detection and the create-review head branch.
  final String? currentBranch;

  /// Short branch names available as create-PR base targets.
  final List<String> baseBranches;

  /// Resolved default base branch for the create form.
  final String? suggestedBaseBranch;

  bool get isBusy => action != null;
  bool get isRefreshing => action == PullRequestAction.refresh;
  bool get hasReview => review != null;
  bool get providerAvailable => identity != null;
  bool get isAuthenticated => authStatus == ForgeAuthStatus.authenticated;
  bool get canManageStack =>
      stackSupported && isAuthenticated && review?.isOpen == true;
  bool get supportsCreation =>
      providerAvailable &&
      isAuthenticated &&
      review == null &&
      suggestedReview == null &&
      unavailableReason == null;

  ReviewChecksRollup get checksRollup => deriveReviewChecksRollup(checks);

  WorkspacePullRequestState copyWith({
    GitRemoteIdentity? identity,
    PullRequestUnavailableReason? unavailableReason,
    ForgeAuthStatus? authStatus,
    HostedReview? review,
    HostedReview? suggestedReview,
    HostedReviewStack? stack,
    bool clearStack = false,
    bool? stackSupported,
    String? stackErrorMessage,
    bool clearStackError = false,
    List<ReviewCheck>? checks,
    List<ReviewComment>? comments,
    bool? linkedManually,
    bool? dismissed,
    String? currentBranch,
    List<String>? baseBranches,
    String? suggestedBaseBranch,
    List<ReviewMergeMethod>? mergeMethods,
    bool? canCloseReview,
    bool? canChangeDraftStatus,
    bool? canComment,
    bool? canEditComments,
    Set<String>? savingCommentIds,
    PullRequestAction? action,
    bool clearAction = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WorkspacePullRequestState(
      identity: identity ?? this.identity,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      authStatus: authStatus ?? this.authStatus,
      review: review ?? this.review,
      suggestedReview: suggestedReview ?? this.suggestedReview,
      stack: clearStack ? null : (stack ?? this.stack),
      stackSupported: stackSupported ?? this.stackSupported,
      stackErrorMessage: clearStackError
          ? null
          : (stackErrorMessage ?? this.stackErrorMessage),
      checks: checks ?? this.checks,
      comments: comments ?? this.comments,
      linkedManually: linkedManually ?? this.linkedManually,
      dismissed: dismissed ?? this.dismissed,
      currentBranch: currentBranch ?? this.currentBranch,
      baseBranches: baseBranches ?? this.baseBranches,
      suggestedBaseBranch: suggestedBaseBranch ?? this.suggestedBaseBranch,
      mergeMethods: mergeMethods ?? this.mergeMethods,
      canCloseReview: canCloseReview ?? this.canCloseReview,
      canChangeDraftStatus: canChangeDraftStatus ?? this.canChangeDraftStatus,
      canComment: canComment ?? this.canComment,
      canEditComments: canEditComments ?? this.canEditComments,
      savingCommentIds: savingCommentIds ?? this.savingCommentIds,
      action: clearAction ? null : (action ?? this.action),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// A cheap signature of the display-relevant data, used by polling to detect
  /// change and adapt its interval.
  String get pollSignature {
    final checkPart = checks
        .map((c) => '${c.name}:${c.status.name}:${c.conclusion.name}')
        .join('|');
    final commentPart = comments
        .map((comment) => '${comment.id}:${comment.createdAt}:${comment.body}')
        .join('|');
    final stackPart = stack == null
        ? ''
        : '${stack!.number}:${stack!.open}:'
              '${stack!.entries.map((entry) => '${entry.review.number}:${entry.review.state.name}:${entry.review.baseBranch}').join('|')}';
    return '${review?.number}:${review?.state.name}:${review?.title}:'
        '${suggestedReview?.number}:${suggestedReview?.state.name}:$dismissed:'
        '${review?.baseBranch}:$stackPart:$checkPart:$commentPart';
  }
}
