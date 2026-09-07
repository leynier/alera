part of 'github_forge_provider.dart';

mixin _GitHubReviewBatch implements ForgeReviewBatchProvider {
  ProcessRunner get _processRunner;

  void _ensureSupportedHost(GitRemoteIdentity identity);

  Object? _decodeJson(String? raw);

  Never _throwClassified(ProcessRunOutput result);

  @override
  Future<ForgeReviewBatch> getReviewBatch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required Set<String> branches,
    required Set<int> reviewNumbers,
  }) async {
    if (branches.isEmpty && reviewNumbers.isEmpty) {
      return const ForgeReviewBatch();
    }
    _ensureSupportedHost(identity);
    final orderedBranches = branches.toList()..sort();
    final orderedNumbers = reviewNumbers.toList()..sort();
    final query = _buildReviewBatchQuery(
      branchCount: orderedBranches.length,
      reviewNumberCount: orderedNumbers.length,
    );
    final arguments = <String>[
      'api',
      'graphql',
      '--hostname',
      identity.host,
      '-f',
      'owner=${identity.owner}',
      '-f',
      'name=${identity.repo}',
      for (final (index, branch) in orderedBranches.indexed) ...<String>[
        '-f',
        'branch$index=$branch',
      ],
      for (final (index, number) in orderedNumbers.indexed) ...<String>[
        '-F',
        'number$index=$number',
      ],
      '-f',
      'query=$query',
    ];

    ProcessRunOutput result;
    try {
      result = await _processRunner.run(
        'gh',
        arguments,
        workingDirectory: repoPath,
      );
    } catch (_) {
      throw const ForgeCliMissing('gh not found');
    }
    if (result.exitCode != 0) {
      if (ghLooksLikeMissingCli(result)) {
        throw const ForgeCliMissing('gh not found');
      }
      _throwClassified(result);
    }
    final decoded = _decodeJson(result.stdout);
    if (decoded is! Map) {
      throw const ForgeRequestFailed('Unexpected gh GraphQL response.');
    }
    final data = _objectMap(decoded['data']);
    final repository = _objectMap(data?['repository']);
    if (repository == null) {
      throw const ForgeRequestFailed(
        'GitHub did not return repository pull requests.',
      );
    }

    final byBranch = <String, ForgeReviewSnapshot>{};
    final byNumber = <int, ForgeReviewSnapshot>{};
    for (final (index, branch) in orderedBranches.indexed) {
      final connection = _objectMap(repository['branch$index']);
      final nodes = connection?['nodes'];
      final node = nodes is List && nodes.isNotEmpty
          ? _objectMap(nodes.first)
          : null;
      final snapshot = _snapshotFromGraphQl(node);
      if (snapshot == null) {
        continue;
      }
      byBranch[branch] = snapshot;
      byNumber[snapshot.review.number] = snapshot;
    }
    for (final (index, requestedNumber) in orderedNumbers.indexed) {
      final snapshot = _snapshotFromGraphQl(
        _objectMap(repository['review$index']),
      );
      if (snapshot == null) {
        continue;
      }
      byNumber[requestedNumber] = snapshot;
      final headBranch = snapshot.review.headBranch;
      if (headBranch != null && headBranch.isNotEmpty) {
        byBranch.putIfAbsent(headBranch, () => snapshot);
      }
    }
    return ForgeReviewBatch(
      byBranch: Map<String, ForgeReviewSnapshot>.unmodifiable(byBranch),
      byNumber: Map<int, ForgeReviewSnapshot>.unmodifiable(byNumber),
    );
  }
}

String _buildReviewBatchQuery({
  required int branchCount,
  required int reviewNumberCount,
}) {
  final variables = <String>[
    r'$owner:String!',
    r'$name:String!',
    for (var index = 0; index < branchCount; index++) '\$branch$index:String!',
    for (var index = 0; index < reviewNumberCount; index++)
      '\$number$index:Int!',
  ];
  // Branch lookup is open-only. Merged/closed PRs are fetched by number when
  // linked or already shown, so a historical PR cannot appear on a workspace
  // that only shares the branch name.
  final selections = <String>[
    for (var index = 0; index < branchCount; index++)
      'branch$index:pullRequests(first:1,headRefName:\$branch$index,'
          'states:[OPEN],'
          'orderBy:{field:CREATED_AT,direction:DESC})'
          '{nodes{...ReviewStatus}}',
    for (var index = 0; index < reviewNumberCount; index++)
      'review$index:pullRequest(number:\$number$index){...ReviewStatus}',
  ];
  return 'query(${variables.join(',')})'
      '{repository(owner:\$owner,name:\$name){${selections.join()}}}'
      'fragment ReviewStatus on PullRequest{'
      'number title state url createdAt updatedAt isDraft mergeable '
      'headRefName baseRefName headRefOid '
      'commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100)'
      '{nodes{__typename '
      '... on CheckRun{name status conclusion detailsUrl}'
      '... on StatusContext{context state targetUrl}'
      '}}}}}}}';
}

ForgeReviewSnapshot? _snapshotFromGraphQl(Map<String, Object?>? json) {
  if (json == null) {
    return null;
  }
  final checks = <ReviewCheck>[];
  final commits = _objectMap(json['commits']);
  final commitNodes = commits?['nodes'];
  if (commitNodes is List && commitNodes.isNotEmpty) {
    final commitNode = _objectMap(commitNodes.first);
    final commit = _objectMap(commitNode?['commit']);
    final rollup = _objectMap(commit?['statusCheckRollup']);
    final contexts = _objectMap(rollup?['contexts']);
    final contextNodes = contexts?['nodes'];
    if (contextNodes is List) {
      for (final raw in contextNodes) {
        final context = _objectMap(raw);
        if (context != null) {
          checks.add(mapGitHubStatusRollupCheck(context));
        }
      }
    }
  }
  return ForgeReviewSnapshot(
    review: mapGitHubReview(json),
    checks: List<ReviewCheck>.unmodifiable(checks),
  );
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return Map<String, Object?>.from(value);
}
