import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';

/// One GitHub-native stack of pull requests, ordered from the bottom layer to
/// the top layer. This is transient forge state and is not persisted locally.
class const HostedReviewStack({
  required final int number,
  required final String baseBranch,
  required final bool open,
  required final List<HostedReviewStackEntry> entries,
  final DateTime? createdAt,
}) {
  HostedReviewStackEntry? entryForReview(int reviewNumber) {
    for (final entry in entries) {
      if (entry.review.number == reviewNumber) {
        return entry;
      }
    }
    return null;
  }

  int? positionForReview(int reviewNumber) =>
      entryForReview(reviewNumber)?.position;

  /// Members at or below [reviewNumber], which GitHub merges atomically when
  /// the stack is merged through that pull request.
  List<HostedReviewStackEntry> entriesThrough(int reviewNumber) {
    final entry = entryForReview(reviewNumber);
    if (entry == null) {
      return const <HostedReviewStackEntry>[];
    }
    return entries
        .where((candidate) => candidate.position <= entry.position)
        .toList(growable: false);
  }
}

class const HostedReviewStackEntry({
  required final HostedReview review,
  required this.position,
}) {
  /// One-based position from the bottom of the stack.
  final int position;
}
