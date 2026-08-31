import 'package:dart_mappable/dart_mappable.dart';

part 'review_check.mapper.dart';

/// Lifecycle phase of a single check run.
@MappableEnum()
enum ReviewCheckStatus { queued, inProgress, completed }

/// Terminal outcome of a check run. `pending` means the run has not concluded.
@MappableEnum()
enum ReviewCheckConclusion {
  success,
  failure,
  cancelled,
  timedOut,
  actionRequired,
  neutral,
  skipped,
  pending,
}

/// A single CI/status check attached to a hosted review, in neutral form.
@MappableClass()
class const ReviewCheck({
  required this.name,
  required this.status,
  required this.conclusion,
  this.url,
}) with ReviewCheckMappable {
  final String name;
  final ReviewCheckStatus status;
  final ReviewCheckConclusion conclusion;
  final String? url;

  factory fromJson(Map<String, Object?> json) =>
      ReviewCheckMapper.fromMap(Map<String, dynamic>.from(json));
}

/// Rolled-up status across all checks of a review.
@MappableEnum()
enum ReviewChecksRollup { none, pending, success, failure }

/// Derives the overall check status. Failure dominates, then still-running
/// checks yield pending, then all-terminal-non-failing yields success. An empty
/// list is [ReviewChecksRollup.none].
ReviewChecksRollup deriveReviewChecksRollup(List<ReviewCheck> checks) {
  if (checks.isEmpty) {
    return ReviewChecksRollup.none;
  }
  var anyPending = false;
  for (final check in checks) {
    switch (check.conclusion) {
      case ReviewCheckConclusion.failure:
      case ReviewCheckConclusion.cancelled:
      case ReviewCheckConclusion.timedOut:
      case ReviewCheckConclusion.actionRequired:
        return ReviewChecksRollup.failure;
      case ReviewCheckConclusion.pending:
        anyPending = true;
      case ReviewCheckConclusion.success:
      case ReviewCheckConclusion.neutral:
      case ReviewCheckConclusion.skipped:
        break;
    }
    if (check.status != ReviewCheckStatus.completed) {
      anyPending = true;
    }
  }
  return anyPending ? ReviewChecksRollup.pending : ReviewChecksRollup.success;
}
