import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';

/// Compact, workspace-facing projection of a hosted review and its checks.
///
/// The sidebar keeps only counts plus at most three failing check names rather
/// than retaining the complete provider response for every workspace.
class const WorkspacePullRequestSummary({
  required this.review,
  required this.checksRollup,
  this.pendingCheckCount = 0,
  this.failedCheckCount = 0,
  this.failingCheckNames = const <String>[],
}) {
  factory WorkspacePullRequestSummary.fromChecks({
    required HostedReview review,
    required List<ReviewCheck> checks,
  }) {
    var pendingCheckCount = 0;
    var failedCheckCount = 0;
    final failingCheckNames = <String>[];
    for (final check in checks) {
      final failed = switch (check.conclusion) {
        ReviewCheckConclusion.failure ||
        ReviewCheckConclusion.cancelled ||
        ReviewCheckConclusion.timedOut ||
        ReviewCheckConclusion.actionRequired => true,
        ReviewCheckConclusion.success ||
        ReviewCheckConclusion.neutral ||
        ReviewCheckConclusion.skipped ||
        ReviewCheckConclusion.pending => false,
      };
      if (failed) {
        failedCheckCount++;
        if (failingCheckNames.length < 3) {
          failingCheckNames.add(check.name);
        }
        continue;
      }
      if (check.status != ReviewCheckStatus.completed ||
          check.conclusion == ReviewCheckConclusion.pending) {
        pendingCheckCount++;
      }
    }
    return WorkspacePullRequestSummary(
      review: review,
      checksRollup: deriveReviewChecksRollup(checks),
      pendingCheckCount: pendingCheckCount,
      failedCheckCount: failedCheckCount,
      failingCheckNames: List<String>.unmodifiable(failingCheckNames),
    );
  }

  final HostedReview review;
  final ReviewChecksRollup checksRollup;
  final int pendingCheckCount;
  final int failedCheckCount;
  final List<String> failingCheckNames;

  bool get checksPending => checksRollup == ReviewChecksRollup.pending;
  bool get checksFailed => checksRollup == ReviewChecksRollup.failure;
  bool get hasMergeConflict =>
      review.state == HostedReviewState.open &&
      review.mergeable == HostedReviewMergeable.conflicting;

  /// Stable display/notification signature. Provider refreshes that produce
  /// the same compact state do not rebuild the sidebar or notify again.
  String get signature => <Object?>[
    review.number,
    review.state.name,
    review.title,
    review.url,
    review.headSha,
    review.mergeable.name,
    checksRollup.name,
    pendingCheckCount,
    failedCheckCount,
    failingCheckNames.join('|'),
  ].join(':');

  @override
  bool operator ==(Object other) =>
      other is WorkspacePullRequestSummary && signature == other.signature;

  @override
  int get hashCode => signature.hashCode;
}
