import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
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
class HostedReview with HostedReviewMappable {
  const HostedReview({
    required this.provider,
    required this.number,
    required this.title,
    required this.state,
    required this.url,
    this.author,
    this.baseBranch,
    this.headBranch,
    this.headSha,
    this.mergeable = HostedReviewMergeable.unknown,
  });

  final GitHostingProvider provider;
  final int number;
  final String title;
  final HostedReviewState state;
  final String url;
  final String? author;
  final String? baseBranch;
  final String? headBranch;
  final String? headSha;
  final HostedReviewMergeable mergeable;

  bool get isOpen =>
      state == HostedReviewState.open || state == HostedReviewState.draft;

  factory HostedReview.fromJson(Map<String, Object?> json) =>
      HostedReviewMapper.fromMap(Map<String, dynamic>.from(json));
}
