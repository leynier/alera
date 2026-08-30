import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'hosted_review.mapper.dart';

/// Lifecycle state of a hosted review (PR / MR).
@MappableEnum()
enum HostedReviewState { open, draft, merged, closed }

/// Whether the review can be merged without conflicts. `unknown` covers
/// providers/states where mergeability has not been computed yet.
@MappableEnum()
enum HostedReviewMergeable { mergeable, conflicting, unknown }

/// Neutral model of a hosted review (GitHub pull request, Azure DevOps pull
/// request, later GitLab merge request, ...). Checks are fetched separately and
/// are not stored here, so the rolled-up check status stays a single source of
/// truth derived from the live check list.
@MappableClass()
class const HostedReview({
  required this.provider,
  required this.number,
  required this.title,
  required this.state,
  required this.url,
  this.createdAt,
  this.author,
  this.baseBranch,
  this.headBranch,
  this.headSha,
  this.headRepositoryUrl,
  this.comparisonBaseSha,
  this.mergeCommitSha,
  this.mergeable = HostedReviewMergeable.unknown,
}) with HostedReviewMappable {
  final GitHostingProvider provider;
  final int number;
  final String title;
  final HostedReviewState state;
  final String url;
  final DateTime? createdAt;
  final String? author;
  final String? baseBranch;
  final String? headBranch;
  final String? headSha;
  final String? headRepositoryUrl;
  final String? comparisonBaseSha;
  final String? mergeCommitSha;
  final HostedReviewMergeable mergeable;

  bool get isOpen =>
      state == HostedReviewState.open || state == HostedReviewState.draft;

  factory fromJson(Map<String, Object?> json) =>
      HostedReviewMapper.fromMap(Map<String, dynamic>.from(json));
}

/// Selects the newest review deterministically. Creation time wins when both
/// candidates provide it; otherwise the larger review number is the fallback.
HostedReview? pickNewestHostedReview(Iterable<HostedReview> reviews) {
  HostedReview? newest;
  for (final candidate in reviews) {
    final current = newest;
    if (current == null || _compareReviewRecency(candidate, current) > 0) {
      newest = candidate;
    }
  }
  return newest;
}

int _compareReviewRecency(HostedReview left, HostedReview right) {
  final leftCreatedAt = left.createdAt;
  final rightCreatedAt = right.createdAt;
  if (leftCreatedAt != null && rightCreatedAt != null) {
    final dateComparison = leftCreatedAt.compareTo(rightCreatedAt);
    if (dateComparison != 0) {
      return dateComparison;
    }
  }
  return left.number.compareTo(right.number);
}
