/// Where a pull-request comment was created.
enum ReviewCommentKind { conversation, review }

/// The provider-neutral source of an editable review comment.
enum ReviewCommentSource { conversation, reviewSummary, reviewThread }

/// Explicit identifiers needed to update an existing review comment.
///
/// [parentId] is the discussion/thread identifier for provider APIs that
/// address a comment through its containing thread.
class ReviewCommentLocator {
  const ReviewCommentLocator({
    required this.source,
    required this.commentId,
    this.parentId,
  });

  final ReviewCommentSource source;
  final String commentId;
  final String? parentId;
}

/// Provider-neutral comment displayed in the pull-request conversation.
class ReviewComment {
  const ReviewComment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.kind,
    this.url,
    this.path,
    this.line,
    this.resolved = false,
    this.locator,
  });

  final String id;
  final String author;
  final String body;
  final DateTime createdAt;
  final ReviewCommentKind kind;
  final String? url;
  final String? path;
  final int? line;
  final bool resolved;
  final ReviewCommentLocator? locator;

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
