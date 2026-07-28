part of 'github_forge_provider.dart';

mixin _GitHubReviewComments {
  static const String _reviewThreadsQuery = r'''
query($owner: String!, $repo: String!, $pr: Int!, $threadsAfter: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $threadsAfter) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          line
          originalLine
          comments(first: 100) {
            pageInfo { hasNextPage endCursor }
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

  static const String _threadCommentsQuery = r'''
query($thread: ID!, $commentsAfter: String) {
  node(id: $thread) {
    ... on PullRequestReviewThread {
      comments(first: 100, after: $commentsAfter) {
        pageInfo { hasNextPage endCursor }
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
''';

  GitHubForgeProvider get _github => this as GitHubForgeProvider;

  Future<List<ReviewComment>> getReviewComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    _github._ensureSupportedHost(identity);
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
    final comments = <ReviewComment>[];
    String? threadsAfter;
    do {
      try {
        final decoded = await _runGraphql(
          identity: identity,
          repoPath: repoPath,
          query: _reviewThreadsQuery,
          fields: <String>[
            'owner=${identity.owner}',
            'repo=${identity.repo}',
            if (threadsAfter != null) 'threadsAfter=$threadsAfter',
          ],
          typedFields: <String>['pr=$number'],
        );
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
        if (reviewThreads is! Map<String, Object?>) {
          break;
        }
        final nodes = reviewThreads['nodes'];
        if (nodes is List) {
          for (final thread in nodes.whereType<Map<String, Object?>>()) {
            comments.addAll(_mapReviewThread(thread));
            try {
              comments.addAll(
                await _fetchRemainingThreadComments(
                  identity: identity,
                  repoPath: repoPath,
                  thread: thread,
                ),
              );
            } on ForgeException {
              // Keep this thread's first page and continue with other threads.
            }
          }
        }
        final next = _nextCursor(reviewThreads);
        if (next == threadsAfter) {
          break;
        }
        threadsAfter = next;
      } on ForgeException {
        return comments;
      }
    } while (threadsAfter != null);
    return comments;
  }

  Future<List<ReviewComment>> _fetchRemainingThreadComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required Map<String, Object?> thread,
  }) async {
    final threadId = thread['id'] as String?;
    final connection = thread['comments'];
    if (threadId == null || connection is! Map<String, Object?>) {
      return const <ReviewComment>[];
    }
    var commentsAfter = _nextCursor(connection);
    final comments = <ReviewComment>[];
    while (commentsAfter != null) {
      final decoded = await _runGraphql(
        identity: identity,
        repoPath: repoPath,
        query: _threadCommentsQuery,
        fields: <String>['thread=$threadId', 'commentsAfter=$commentsAfter'],
      );
      final data = decoded['data'];
      final node = data is Map<String, Object?> ? data['node'] : null;
      final page = node is Map<String, Object?> ? node['comments'] : null;
      if (page is! Map<String, Object?>) {
        break;
      }
      final nodes = page['nodes'];
      if (nodes is List) {
        comments.addAll(_mapReviewThreadNodes(thread, nodes));
      }
      final next = _nextCursor(page);
      if (next == commentsAfter) {
        break;
      }
      commentsAfter = next;
    }
    return comments;
  }

  Future<Map<String, Object?>> _runGraphql({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String query,
    List<String> fields = const <String>[],
    List<String> typedFields = const <String>[],
  }) async {
    final output = await _github._run(<String>[
      'api',
      '--hostname',
      identity.host,
      'graphql',
      '-f',
      'query=$query',
      for (final field in fields) ...<String>['-f', field],
      for (final field in typedFields) ...<String>['-F', field],
    ], repoPath);
    final decoded = _github._decodeJson(output);
    if (decoded is! Map<String, Object?>) {
      throw const ForgeRequestFailed('Unexpected gh GraphQL output.');
    }
    return decoded;
  }

  String? _nextCursor(Map<String, Object?> connection) {
    final pageInfo = connection['pageInfo'];
    if (pageInfo is! Map<String, Object?> || pageInfo['hasNextPage'] != true) {
      return null;
    }
    return pageInfo['endCursor'] as String?;
  }

  Iterable<ReviewComment> _mapReviewThread(Map<String, Object?> thread) sync* {
    final comments = thread['comments'];
    final nodes = comments is Map<String, Object?> ? comments['nodes'] : null;
    if (nodes is! List) {
      return;
    }
    yield* _mapReviewThreadNodes(thread, nodes);
  }

  Iterable<ReviewComment> _mapReviewThreadNodes(
    Map<String, Object?> thread,
    List<Object?> nodes,
  ) sync* {
    final threadId = thread['id'] as String? ?? 'unknown';
    final line = thread['line'] as int? ?? thread['originalLine'] as int?;
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
