part of 'azure_devops_forge_provider.dart';

mixin _AzureDevOpsReviewComments {
  AzureDevOpsForgeProvider get _azure => this as AzureDevOpsForgeProvider;

  Future<List<ReviewComment>> getReviewComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final project = _project(identity);
    final output = await _azure._run(<String>[
      'devops',
      'invoke',
      '--area',
      'git',
      '--resource',
      'pullRequestThreads',
      '--route-parameters',
      'project=$project',
      'repositoryId=${identity.repo}',
      'pullRequestId=$number',
      '--http-method',
      'GET',
      '--api-version',
      '7.1',
      '--organization',
      azureOrgUrl(identity),
      '--output',
      'json',
    ], repoPath);
    final decoded = _azure._decodeJson(output);
    final rawThreads = switch (decoded) {
      {'value': final List<Object?> value} => value,
      final List<Object?> value => value,
      _ => const <Object?>[],
    };
    final comments = <ReviewComment>[];
    for (final rawThread in rawThreads) {
      if (rawThread is! Map<String, Object?> ||
          rawThread['isDeleted'] == true) {
        continue;
      }
      comments.addAll(_mapThread(rawThread));
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
    final project = _project(identity);
    final tempDir = await Directory.systemTemp.createTemp('alera-pr-comment');
    try {
      final bodyFile = File(p.join(tempDir.path, 'body.json'));
      await bodyFile.writeAsString(
        AzureDevOpsForgeProvider.commentThreadBodyJson(body),
      );
      await _azure._run(<String>[
        'devops',
        'invoke',
        '--area',
        'git',
        '--resource',
        'pullRequestThreads',
        '--route-parameters',
        'project=$project',
        'repositoryId=${identity.repo}',
        'pullRequestId=$number',
        '--http-method',
        'POST',
        '--api-version',
        '7.1',
        '--in-file',
        bodyFile.path,
        '--organization',
        azureOrgUrl(identity),
        '--output',
        'json',
      ], repoPath);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> updateReviewComment({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCommentLocator locator,
    required String body,
  }) async {
    final project = _project(identity);
    final threadId = locator.parentId;
    if (threadId == null || threadId.isEmpty) {
      throw const ForgeRequestFailed(
        'The Azure DevOps comment thread could not be determined.',
      );
    }
    final tempDir = await Directory.systemTemp.createTemp('alera-pr-comment');
    try {
      final bodyFile = File(p.join(tempDir.path, 'body.json'));
      await bodyFile.writeAsString(
        AzureDevOpsForgeProvider.commentBodyJson(body),
      );
      await _azure._run(<String>[
        'devops',
        'invoke',
        '--area',
        'git',
        '--resource',
        'pullRequestThreadComments',
        '--route-parameters',
        'project=$project',
        'repositoryId=${identity.repo}',
        'pullRequestId=$number',
        'threadId=$threadId',
        'commentId=${locator.commentId}',
        '--http-method',
        'PATCH',
        '--api-version',
        '7.1',
        '--in-file',
        bodyFile.path,
        '--organization',
        azureOrgUrl(identity),
        '--output',
        'json',
      ], repoPath);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Iterable<ReviewComment> _mapThread(Map<String, Object?> thread) sync* {
    final threadId = '${thread['id']}';
    final context = thread['threadContext'];
    final path = context is Map<String, Object?>
        ? context['filePath'] as String?
        : null;
    final rightStart = context is Map<String, Object?>
        ? context['rightFileStart']
        : null;
    final line = rightStart is Map<String, Object?>
        ? rightStart['line'] as int?
        : null;
    final status = '${thread['status']}'.toLowerCase();
    final resolved =
        status == 'fixed' ||
        status == 'closed' ||
        status == 'bydesign' ||
        status == 'wontfix';
    final rawComments = thread['comments'];
    if (rawComments is! List) {
      return;
    }
    for (final rawComment in rawComments) {
      if (rawComment is! Map<String, Object?> ||
          rawComment['isDeleted'] == true ||
          rawComment['commentType'] == 3 ||
          '${rawComment['commentType']}'.toLowerCase() == 'system') {
        continue;
      }
      final authorData = rawComment['author'];
      final author = authorData is Map<String, Object?>
          ? authorData['displayName'] as String? ??
                authorData['uniqueName'] as String?
          : null;
      yield ReviewComment(
        id: '$threadId:${rawComment['id']}',
        author: author ?? 'Unknown author',
        body: rawComment['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(rawComment['publishedDate'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        kind: path == null
            ? ReviewCommentKind.conversation
            : ReviewCommentKind.review,
        path: path,
        line: line,
        resolved: resolved,
        locator: rawComment['id'] == null
            ? null
            : ReviewCommentLocator(
                source: path == null
                    ? ReviewCommentSource.conversation
                    : ReviewCommentSource.reviewThread,
                commentId: '${rawComment['id']}',
                parentId: threadId,
              ),
      );
    }
  }

  String _project(GitRemoteIdentity identity) {
    final project = identity.project;
    if (project == null || project.isEmpty) {
      throw const ForgeRequestFailed(
        'The Azure DevOps project could not be determined from the remote.',
      );
    }
    return project;
  }
}
