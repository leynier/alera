/// Where a pull-request comment was created.
enum ReviewCommentKind { conversation, review }

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
}
