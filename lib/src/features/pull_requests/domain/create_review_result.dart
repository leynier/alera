import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';

/// Typed failure categories for review creation. Providers map their CLI/API
/// errors into these instead of leaking raw stderr strings upward.
enum CreateReviewErrorCode {
  notAuthenticated,
  cliMissing,
  pushFailed,
  alreadyExists,
  blocked,
  unknown,
}

/// Outcome of a create-review request. Discriminated so callers handle success
/// and typed failure explicitly, never a bare null.
sealed class const CreateReviewResult();

class const CreateReviewSuccess(final HostedReview review)
    extends CreateReviewResult;

class const CreateReviewFailure({
  required final CreateReviewErrorCode code,
  required final String message,
}) extends CreateReviewResult;
