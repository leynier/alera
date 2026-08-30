import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'linked_review.mapper.dart';

/// Per-workspace review intent, persisted via the runtime host. A linked review
/// points at the review to display; a dismissal identifies the exact review to
/// ignore while allowing a different review on the branch to be auto-detected.
/// Legacy dismissals without provider/number remain readable.
@MappableClass()
class const LinkedReview({
  required this.workspaceId,
  required this.linkedAt,
  this.dismissed = false,
  this.provider,
  this.number,
  this.url,
}) with LinkedReviewMappable {
  /// A concrete link to review [number].
  factory linked({
    required String workspaceId,
    required GitHostingProvider provider,
    required int number,
    required String url,
    DateTime? linkedAt,
  }) => LinkedReview(
    workspaceId: workspaceId,
    provider: provider,
    number: number,
    url: url,
    linkedAt: (linkedAt ?? DateTime.now()).toUtc(),
  );

  /// A dismissal for one review. Optional identity fields preserve backwards
  /// compatibility with legacy records that suppressed the whole workspace.
  factory dismissal({
    required String workspaceId,
    GitHostingProvider? provider,
    int? number,
    String? url,
    DateTime? linkedAt,
  }) => LinkedReview(
    workspaceId: workspaceId,
    dismissed: true,
    provider: provider,
    number: number,
    url: url,
    linkedAt: (linkedAt ?? DateTime.now()).toUtc(),
  );

  final String workspaceId;
  final bool dismissed;
  final GitHostingProvider? provider;
  final int? number;
  final String? url;
  final DateTime linkedAt;

  /// Whether this record points at a concrete review to display.
  bool get hasReview => !dismissed && number != null && provider != null;

  /// Whether this dismissal identifies one exact review.
  bool get hasDismissedReview =>
      dismissed && number != null && provider != null;

  factory fromJson(Map<String, Object?> json) =>
      LinkedReviewMapper.fromMap(Map<String, dynamic>.from(json));
}
