import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';

/// A git hosting provider integration. One implementation per forge, each
/// wrapping that forge's official CLI. The interface is neutral: no
/// provider-specific parameters leak in, and callers dispatch through the
/// `ForgeProviderRegistry`.
///
/// Read methods that genuinely find nothing return `null` / an empty list;
/// authentication, missing-CLI, and transport problems throw a
/// [ForgeException] subtype so absence is never confused with failure.
abstract interface class ForgeProvider {
  /// The provider this integration serves.
  GitHostingProvider get id;

  /// Whether this provider can create reviews (some are read-only).
  bool get supportsReviewCreation;

  /// Merge strategies this provider can execute.
  List<ReviewMergeMethod> get supportedMergeMethods;

  /// Whether this provider can close an open review without merging it.
  bool get supportsReviewClosure;

  /// Whether this provider can convert reviews between draft and ready states.
  bool get supportsReviewDraftConversion;

  /// Whether this provider can read and create pull-request comments.
  bool get supportsReviewComments;

  /// Whether this provider can update existing pull-request comments.
  bool get supportsReviewCommentEditing;

  /// Reports whether the provider's CLI is installed and authenticated for the
  /// host in [identity]. Never throws.
  Future<ForgeAuthStatus> checkAuth({required GitRemoteIdentity identity});

  /// The open review whose source branch is [branch], or null when the branch
  /// has no open review. [repoPath] is the local checkout used as the CLI
  /// working directory.
  Future<HostedReview?> getReviewForBranch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String branch,
  });

  /// The review identified by [number], or null when it does not exist.
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  });

  /// The CI/status checks attached to review [number]. Empty when the review
  /// has no checks.
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  });

  /// Detail metadata for one check of review [number], matched by [check]'s
  /// name (and url when names are ambiguous). Null when the check cannot be
  /// found anymore.
  Future<ReviewCheckDetails?> getCheckDetails({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCheck check,
  });

  /// Conversation and inline review comments attached to review [number].
  Future<List<ReviewComment>> getReviewComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  });

  /// Adds a top-level conversation comment to review [number].
  Future<void> addReviewComment({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required String body,
  });

  /// Replaces the complete Markdown body of an existing review comment.
  /// Provider permissions are enforced by the provider endpoint.
  Future<void> updateReviewComment({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCommentLocator locator,
    required String body,
  });

  /// Creates a review from [input]. The head branch is expected to already be
  /// pushed to the remote (the caller pushes first). Returns a discriminated
  /// success/failure result rather than throwing for expected failures.
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  });

  /// Updates title and/or base branch of review [number]. Callers must not
  /// pass an empty [input]. Returns a discriminated result, mirroring
  /// [createReview].
  Future<UpdateReviewResult> updateReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required UpdateReviewInput input,
  });

  /// Merges review [number] using [method]. Expected provider failures throw a
  /// typed [ForgeException].
  Future<void> mergeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewMergeMethod method,
  });

  /// Closes review [number] without merging it.
  Future<void> closeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  });

  /// Sets whether review [number] is a draft.
  Future<void> setReviewDraft({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required bool draft,
  });
}
