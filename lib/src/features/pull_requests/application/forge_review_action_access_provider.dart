import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_action_access.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';

abstract interface class ForgeReviewActionAccessProvider {
  Future<ReviewActionAccess> reviewActionAccess({
    required GitRemoteIdentity identity,
    required String repoPath,
    required HostedReview review,
  });
}
