import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';

/// Why a review cannot be created from the current workspace state.
enum ReviewCreationBlockedReason {
  detachedHead,
  onDefaultBranch,
  dirtyWorkingTree,
  noCommitsAhead,
  noUpstreamBranch,
  notAuthenticated,
  cliMissing,
  existingReview,
  providerUnsupported,
}

/// Result of the pre-flight check run before offering "Create PR". When
/// [canCreate] is false, [blockedReason] explains why; [existingReview] is set
/// when the branch already has an open review.
class ReviewCreationEligibility {
  const new({required this.canCreate, this.blockedReason, this.existingReview});

  const new allowed()
    : canCreate = true,
      blockedReason = null,
      existingReview = null;

  const new blocked(ReviewCreationBlockedReason reason, {this.existingReview})
    : canCreate = false,
      blockedReason = reason;

  final bool canCreate;
  final ReviewCreationBlockedReason? blockedReason;
  final HostedReview? existingReview;
}
