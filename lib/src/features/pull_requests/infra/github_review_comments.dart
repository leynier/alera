part of 'github_forge_provider.dart';

mixin _GitHubReviewComments {
  static const String _reviewThreadsQuery = r'''
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          line
          originalLine
          comments(first: 100) {
            nodes {
              databaseId
              author { login }
              body
              createdAt
              url
              path
            }
          }
        }
      }
    }
  }
}
''';

  GitHubForgeProvider get _github => this as GitHubForgeProvider;

  Future<List<ReviewComment>> getReviewComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final conversationFuture = _safeFetchCommentEntries(
      identity: identity,
      repoPath: repoPath,
      endpoint:
          'repos/${identity.owner}/${identity.repo}/issues/$number/comments'
          '?per_page=100',
    );
    final threadsFuture = _safeFetchReviewThreads(
      identity: identity,
      repoPath: repoPath,
      number: number,
    );
    final reviewsFuture = _safeFetchCommentEntries(
      identity: identity,
      repoPath: repoPath,
      endpoint:
          'repos/${identity.owner}/${identity.repo}/pulls/$number/reviews'
          '?per_page=100',
    );
    final conversation = await conversationFuture;
    final threads = await threadsFuture;
    final reviews = await reviewsFuture;
    final comments = <ReviewComment>[
      for (final entry in conversation)
        _mapRestComment(
          entry,
          kind: ReviewCommentKind.conversation,
          idPrefix: 'issue',
        ),
      ...threads,
      for (final entry in reviews)
        if ((entry['body'] as String? ?? '').trim().isNotEmpty)
          _mapRestComment(
            entry,
            kind: ReviewCommentKind.conversation,
            idPrefix: 'review',
            createdAtField: 'submitted_at',
          ),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return comments;
  }

  Future<void> addReviewComment({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required String body,
  }) async {
    await _github._run(<String>[
      'pr',
      'comment',
      '$number',
      '--repo',
      _github._repoSlug(identity),
      '--body',
      body,
    ], repoPath);
  }

  Future<List<Map<String, Object?>>> _fetchCommentEntries({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String endpoint,
  }) async {
    final output = await _github._run(<String>[
      'api',
      '--hostname',
      identity.host,
      '--paginate',
      '--slurp',
      endpoint,
    ], repoPath);
    final decoded = _github._decodeJson(output);
    if (decoded is! List) {
      return const <Map<String, Object?>>[];
    }
    final entries = <Map<String, Object?>>[];
    for (final page in decoded) {
      if (page is List) {
        entries.addAll(page.whereType<Map<String, Object?>>());
      } else if (page is Map<String, Object?>) {
        entries.add(page);
      }
    }
    return entries;
  }

  Future<List<Map<String, Object?>>> _safeFetchCommentEntries({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String endpoint,
  }) async {
    try {
      return await _fetchCommentEntries(
        identity: identity,
        repoPath: repoPath,
        endpoint: endpoint,
      );
    } on ForgeException {
      return const <Map<String, Object?>>[];
    }
  }

  Future<List<ReviewComment>> _safeFetchReviewThreads({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    try {
      final output = await _github._run(<String>[
        'api',
        '--hostname',
        identity.host,
        'graphql',
        '-f',
        'query=$_reviewThreadsQuery',
        '-f',
        'owner=${identity.owner}',
        '-f',
        'repo=${identity.repo}',
        '-F',
        'pr=$number',
      ], repoPath);
      final decoded = _github._decodeJson(output);
      if (decoded is! Map<String, Object?>) {
        return const <ReviewComment>[];
      }
      final data = decoded['data'];
      final repository = data is Map<String, Object?>
          ? data['repository']
          : null;
      final pullRequest = repository is Map<String, Object?>
          ? repository['pullRequest']
          : null;
      final reviewThreads = pullRequest is Map<String, Object?>
          ? pullRequest['reviewThreads']
          : null;
      final nodes = reviewThreads is Map<String, Object?>
          ? reviewThreads['nodes']
          : null;
      if (nodes is! List) {
        return const <ReviewComment>[];
      }
      return <ReviewComment>[
        for (final thread in nodes)
          if (thread is Map<String, Object?>) ..._mapReviewThread(thread),
      ];
    } on ForgeException {
      return const <ReviewComment>[];
    }
  }

  Iterable<ReviewComment> _mapReviewThread(Map<String, Object?> thread) sync* {
    final threadId = thread['id'] as String? ?? 'unknown';
    final line = thread['line'] as int? ?? thread['originalLine'] as int?;
    final comments = thread['comments'];
    final nodes = comments is Map<String, Object?> ? comments['nodes'] : null;
    if (nodes is! List) {
      return;
    }
    for (final node in nodes) {
      if (node is! Map<String, Object?>) {
        continue;
      }
      final authorData = node['author'];
      yield ReviewComment(
        id: 'thread:$threadId:${node['databaseId']}',
        author: authorData is Map<String, Object?>
            ? authorData['login'] as String? ?? 'Unknown Author'
            : 'Unknown Author',
        body: node['body'] as String? ?? '',
        createdAt:
            DateTime.tryParse(node['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        kind: ReviewCommentKind.review,
        url: node['url'] as String?,
        path: node['path'] as String?,
        line: line,
        resolved: thread['isResolved'] == true,
      );
    }
  }

  ReviewComment _mapRestComment(
    Map<String, Object?> entry, {
    required ReviewCommentKind kind,
    required String idPrefix,
    String createdAtField = 'created_at',
  }) {
    final user = entry['user'];
    final author = user is Map<String, Object?>
        ? user['login'] as String?
        : null;
    return ReviewComment(
      id: '$idPrefix:${entry['id']}',
      author: author ?? 'Unknown Author',
      body: entry['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(entry[createdAtField] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      kind: kind,
      url: entry['html_url'] as String?,
    );
  }
}
