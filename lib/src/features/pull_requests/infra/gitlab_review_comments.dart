part of 'gitlab_forge_provider.dart';

mixin _GitLabReviewComments {
  GitLabForgeProvider get _gitlab => this as GitLabForgeProvider;

  bool get supportsReviewComments => true;

  Future<List<ReviewComment>> getReviewComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final output = await _gitlab._api(
      identity,
      repoPath,
      '${_gitlab._projectEndpoint(identity)}/merge_requests/$number/discussions'
      '?per_page=100',
      paginate: true,
    );
    final decoded = _gitlab._decodeNdjson(output);
    final comments = <ReviewComment>[];
    for (final rawDiscussion in decoded.whereType<Map>()) {
      final discussion = Map<String, Object?>.from(rawDiscussion);
      final notes = discussion['notes'];
      if (notes is! List) {
        continue;
      }
      for (final rawNote in notes.whereType<Map>()) {
        final note = Map<String, Object?>.from(rawNote);
        if (note['system'] == true) {
          continue;
        }
        final author = note['author'];
        final position = note['position'];
        final positioned = position is Map;
        comments.add(
          ReviewComment(
            id: 'discussion:${discussion['id']}:${note['id']}',
            author: author is Map
                ? author['username'] as String? ??
                      author['name'] as String? ??
                      'Unknown Author'
                : 'Unknown Author',
            body: note['body'] as String? ?? '',
            createdAt:
                DateTime.tryParse(note['created_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            kind: positioned
                ? ReviewCommentKind.review
                : ReviewCommentKind.conversation,
            url: note['url'] as String?,
            path: positioned
                ? position['new_path'] as String? ??
                      position['old_path'] as String?
                : null,
            line: positioned
                ? (position['new_line'] as num? ?? position['old_line'] as num?)
                      ?.toInt()
                : null,
            resolved: positioned && note['resolved'] == true,
          ),
        );
      }
    }
    comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return comments;
  }

  Future<void> addReviewComment({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required String body,
  }) async {
    await _gitlab._api(
      identity,
      repoPath,
      '${_gitlab._projectEndpoint(identity)}/merge_requests/$number/notes',
      method: 'POST',
      fields: <String>['body=$body'],
    );
  }
}
