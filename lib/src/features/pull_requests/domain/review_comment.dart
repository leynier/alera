/// Where a pull-request comment was created.
enum ReviewCommentKind { conversation, review }

/// The provider-neutral source of an editable review comment.
enum ReviewCommentSource { conversation, reviewSummary, reviewThread }

/// Explicit identifiers needed to update an existing review comment.
///
/// [parentId] is the discussion/thread identifier for provider APIs that
/// address a comment through its containing thread.
class const ReviewCommentLocator({
  required final ReviewCommentSource source,
  required final String commentId,
  final String? parentId,
});

/// Provider-neutral comment displayed in the pull-request conversation.
class const ReviewComment({
  required final String id,
  required final String author,
  required final String body,
  required final DateTime createdAt,
  required final ReviewCommentKind kind,
  final String? url,
  final String? path,
  final int? line,
  final bool resolved = false,
  final ReviewCommentLocator? locator,
}) {
  ReviewComment copyWith({String? body, ReviewCommentLocator? locator}) {
    return ReviewComment(
      id: id,
      author: author,
      body: body ?? this.body,
      createdAt: createdAt,
      kind: kind,
      url: url,
      path: path,
      line: line,
      resolved: resolved,
      locator: locator ?? this.locator,
    );
  }
}
