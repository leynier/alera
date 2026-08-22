import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';

/// Optional forge capability for native pull-request stacks. Providers that do
/// not implement this interface keep their existing single-review behavior.
abstract interface class ForgeStackProvider {
  /// The stack containing [reviewNumber], or null when the pull request is not
  /// currently part of a native stack.
  Future<HostedReviewStack?> getStackForReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
  });

  /// Creates a stack from [reviewNumbers] or appends them to [stackNumber].
  /// Review numbers are ordered from the bottom layer to the top layer.
  Future<HostedReviewStack> linkReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required List<int> reviewNumbers,
    int? stackNumber,
    String? baseBranch,
  });

  /// Atomically merges the stack through [reviewNumber].
  Future<void> mergeReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
    required ReviewMergeMethod method,
  });
}
