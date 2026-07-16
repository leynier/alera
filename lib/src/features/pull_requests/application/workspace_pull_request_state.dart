import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';

/// Why the pull-request panel has no provider to work with.
enum PullRequestUnavailableReason { noRemote, undetectable, unsupported }

/// In-flight action for busy indicators.
enum PullRequestAction { refresh, link, unlink, create, update }

/// Immutable state of the pull-request panel for one workspace.
class WorkspacePullRequestState {
  const WorkspacePullRequestState({
    this.identity,
    this.unavailableReason,
    this.authStatus = ForgeAuthStatus.unknown,
    this.review,
    this.checks = const <ReviewCheck>[],
    this.linkedManually = false,
    this.dismissed = false,
    this.currentBranch,
    this.baseBranches = const <String>[],
    this.suggestedBaseBranch,
    this.action,
    this.errorMessage,
  });

  final GitRemoteIdentity? identity;
  final PullRequestUnavailableReason? unavailableReason;
  final ForgeAuthStatus authStatus;
  final HostedReview? review;
  final List<ReviewCheck> checks;
  final bool linkedManually;
  final bool dismissed;

  /// The current branch of the controlled repository, or null when detached or
  /// unavailable. Drives auto-detection and the create-review head branch.
  final String? currentBranch;

  /// Short branch names available as create-PR base targets.
  final List<String> baseBranches;

  /// Resolved default base branch for the create form.
  final String? suggestedBaseBranch;

  final PullRequestAction? action;
  final String? errorMessage;

  bool get isBusy => action != null;
  bool get isRefreshing => action == PullRequestAction.refresh;
  bool get hasReview => review != null;
  bool get providerAvailable => identity != null;
  bool get isAuthenticated => authStatus == ForgeAuthStatus.authenticated;
  bool get supportsCreation =>
      providerAvailable &&
      isAuthenticated &&
      review == null &&
      unavailableReason == null;

  ReviewChecksRollup get checksRollup => deriveReviewChecksRollup(checks);

  WorkspacePullRequestState copyWith({
    GitRemoteIdentity? identity,
    PullRequestUnavailableReason? unavailableReason,
    ForgeAuthStatus? authStatus,
    HostedReview? review,
    List<ReviewCheck>? checks,
    bool? linkedManually,
    bool? dismissed,
    String? currentBranch,
    List<String>? baseBranches,
    String? suggestedBaseBranch,
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
      checks: checks ?? this.checks,
      linkedManually: linkedManually ?? this.linkedManually,
      dismissed: dismissed ?? this.dismissed,
      currentBranch: currentBranch ?? this.currentBranch,
      baseBranches: baseBranches ?? this.baseBranches,
      suggestedBaseBranch: suggestedBaseBranch ?? this.suggestedBaseBranch,
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
    return '${review?.number}:${review?.state.name}:${review?.title}:'
        '${review?.baseBranch}:$checkPart';
  }
}
