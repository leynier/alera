import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';

/// Typed failure categories for review updates. Providers map their CLI/API
/// errors into these instead of leaking raw stderr strings upward.
enum UpdateReviewErrorCode { notAuthenticated, cliMissing, blocked, unknown }

/// Outcome of an update-review request. Discriminated so callers handle
/// success and typed failure explicitly, never a bare null.
sealed class const UpdateReviewResult();

class const UpdateReviewSuccess(final HostedReview review)
    extends UpdateReviewResult;

class const UpdateReviewFailure({
  required final UpdateReviewErrorCode code,
  required final String message,
}) extends UpdateReviewResult;
