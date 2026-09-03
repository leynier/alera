import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';

/// One hosted review plus the check runs attached to its current head commit.
class const ForgeReviewSnapshot({
  required this.review,
  this.checks = const <ReviewCheck>[],
}) {
  final HostedReview review;
  final List<ReviewCheck> checks;
}

/// Results of one provider request, indexed both by branch and review number.
class const ForgeReviewBatch({
  this.byBranch = const <String, ForgeReviewSnapshot>{},
  this.byNumber = const <int, ForgeReviewSnapshot>{},
}) {
  final Map<String, ForgeReviewSnapshot> byBranch;
  final Map<int, ForgeReviewSnapshot> byNumber;
}

/// Optional fast path for forge implementations that can retrieve multiple
/// branches and review numbers in one request. The monitor falls back to the
/// regular forge methods when this interface is unavailable.
abstract interface class ForgeReviewBatchProvider {
  Future<ForgeReviewBatch> getReviewBatch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required Set<String> branches,
    required Set<int> reviewNumbers,
  });
}
