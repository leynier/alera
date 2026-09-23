import 'dart:collection';

import 'review_comment.dart';

/// Partial comments remain displayable but cannot prove all feedback resolved.
class ReviewCommentLoad extends UnmodifiableListView<ReviewComment> {
  ReviewCommentLoad(super.source, {required this.complete});

  final bool complete;
}

bool reviewCommentsComplete(List<ReviewComment> comments) =>
    comments is! ReviewCommentLoad || comments.complete;
