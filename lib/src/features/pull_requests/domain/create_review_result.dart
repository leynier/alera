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
sealed class CreateReviewResult {
  const CreateReviewResult();
}

class CreateReviewSuccess extends CreateReviewResult {
  const CreateReviewSuccess(this.review);

  final HostedReview review;
}

class CreateReviewFailure extends CreateReviewResult {
  const CreateReviewFailure({required this.code, required this.message});

  final CreateReviewErrorCode code;
  final String message;
}
