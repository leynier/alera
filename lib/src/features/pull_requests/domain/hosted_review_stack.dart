import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';

/// One GitHub-native stack of pull requests, ordered from the bottom layer to
/// the top layer. This is transient forge state and is not persisted locally.
class HostedReviewStack {
  const HostedReviewStack({
    required this.number,
    required this.baseBranch,
    required this.open,
    required this.entries,
    this.createdAt,
  });

  final int number;
  final String baseBranch;
  final bool open;
  final DateTime? createdAt;
  final List<HostedReviewStackEntry> entries;

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

class HostedReviewStackEntry {
  const HostedReviewStackEntry({required this.review, required this.position});

  final HostedReview review;

  /// One-based position from the bottom of the stack.
  final int position;
}
