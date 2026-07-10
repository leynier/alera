import 'dart:convert';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// [ForgeProvider] for GitHub, wrapping the official `gh` CLI. Authentication
/// relies on the user being logged in via `gh auth login`. Follows the
/// `GitHubStarService` pattern: constructor-injected [ProcessRunner], typed
/// errors instead of leaked stderr.
class GitHubForgeProvider implements ForgeProvider {
  const GitHubForgeProvider(this._processRunner);

  final ProcessRunner _processRunner;

  static const List<String> _reviewJsonFields = <String>[
    'number',
    'title',
    'state',
    'url',
    'isDraft',
    'mergeable',
    'headRefName',
    'baseRefName',
    'headRefOid',
    'author',
  ];

  @override
  GitHostingProvider get id => GitHostingProvider.github;

  @override
  bool get supportsReviewCreation => true;

  /// `gh` accepts `[HOST/]OWNER/REPO`; the host prefix is only needed for
  /// GitHub Enterprise hosts.
  String _repoSlug(GitRemoteIdentity identity) {
    if (identity.host == 'github.com') {
      return '${identity.owner}/${identity.repo}';
    }
    return '${identity.host}/${identity.owner}/${identity.repo}';
  }

  @override
  Future<ForgeAuthStatus> checkAuth({
    required GitRemoteIdentity identity,
  }) async {
    try {
      final result = await _processRunner.run('gh', <String>[
        'auth',
        'status',
        '--hostname',
        identity.host,
      ]);
      if (result.exitCode == 0) {
        return ForgeAuthStatus.authenticated;
      }
      if (_looksLikeMissingCli(result)) {
        return ForgeAuthStatus.cliMissing;
      }
      return ForgeAuthStatus.notAuthenticated;
    } catch (_) {
      return ForgeAuthStatus.cliMissing;
    }
  }

  @override
  Future<HostedReview?> getReviewForBranch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String branch,
  }) async {
    final output = await _run(
      <String>[
        'pr',
        'list',
        '--repo',
        _repoSlug(identity),
        '--head',
        branch,
        '--state',
        'open',
        '--limit',
        '1',
        '--json',
        _reviewJsonFields.join(','),
      ],
      repoPath,
    );
    final decoded = _decodeJson(output);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }
    return _mapReview(decoded.first as Map<String, Object?>);
  }

  @override
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final output = await _run(
      <String>[
        'pr',
        'view',
        '$number',
        '--repo',
        _repoSlug(identity),
        '--json',
        _reviewJsonFields.join(','),
      ],
      repoPath,
      allowNotFound: true,
    );
    if (output == null) {
      return null;
    }
    final decoded = _decodeJson(output);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    return _mapReview(decoded);
  }

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    // `gh pr checks` exits non-zero when checks are pending or failing, so the
    // exit code is not a success signal — parse stdout regardless and only
    // treat a genuine "no checks" as an empty list.
    ProcessRunOutput result;
    try {
      result = await _processRunner.run('gh', <String>[
        'pr',
        'checks',
        '$number',
        '--repo',
        _repoSlug(identity),
        '--json',
        'name,state,bucket,link',
      ], workingDirectory: repoPath);
    } catch (_) {
      throw const ForgeCliMissing('gh not found');
    }
    if (_looksLikeMissingCli(result)) {
      throw const ForgeCliMissing('gh not found');
    }
    final stdout = result.stdout.trim();
    if (stdout.isEmpty) {
      if (_mentionsNoChecks(result.stderr)) {
        return const <ReviewCheck>[];
      }
      _throwClassified(result);
    }
    final decoded = _tryDecode(stdout);
    if (decoded is! List) {
      if (_mentionsNoChecks(result.stderr)) {
        return const <ReviewCheck>[];
      }
      throw ForgeRequestFailed('Unexpected gh pr checks output: $stdout');
    }
    return <ReviewCheck>[
      for (final entry in decoded)
        if (entry is Map<String, Object?>) _mapCheck(entry),
    ];
  }

  @override
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  }) async {
    ProcessRunOutput result;
    try {
      result = await _processRunner.run('gh', <String>[
        'pr',
        'create',
        '--repo',
        _repoSlug(identity),
        '--base',
        input.baseBranch,
        '--head',
        input.headBranch,
        '--title',
        input.title,
        '--body',
        input.body ?? '',
        if (input.draft) '--draft',
      ], workingDirectory: repoPath);
    } catch (_) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.cliMissing,
        message: 'The gh CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return _mapCreateFailure(result);
    }
    final number = _pullNumberFromUrl(result.stdout.trim());
    if (number != null) {
      final review = await getReviewByNumber(
        identity: identity,
        repoPath: repoPath,
        number: number,
      );
      if (review != null) {
        return CreateReviewSuccess(review);
      }
    }
    // Created but could not re-read; surface a minimal success from the URL.
    final url = _firstUrl(result.stdout.trim());
    if (url != null && number != null) {
      return CreateReviewSuccess(
        HostedReview(
          provider: GitHostingProvider.github,
          number: number,
          title: input.title,
          state: input.draft
              ? HostedReviewState.draft
              : HostedReviewState.open,
          url: url,
          baseBranch: input.baseBranch,
          headBranch: input.headBranch,
        ),
      );
    }
    return const CreateReviewFailure(
      code: CreateReviewErrorCode.unknown,
      message: 'The pull request was created but could not be read back.',
    );
  }

  /// Runs a read `gh` command expected to emit JSON on stdout. Throws a typed
  /// [ForgeException] on failure. When [allowNotFound] is set, a not-found
  /// result yields null instead of throwing.
  Future<String?> _run(
    List<String> arguments,
    String repoPath, {
    bool allowNotFound = false,
  }) async {
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
    if (result.exitCode == 0) {
      return result.stdout;
    }
    if (_looksLikeMissingCli(result)) {
      throw const ForgeCliMissing('gh not found');
    }
    if (allowNotFound && _mentionsNotFound(result.stderr)) {
      return null;
    }
    _throwClassified(result);
  }

  Never _throwClassified(ProcessRunOutput result) {
    final stderr = result.stderr.toLowerCase();
    if (stderr.contains('not logged') ||
        stderr.contains('authentication') ||
        stderr.contains('gh auth login')) {
      throw ForgeNotAuthenticated(result.stderr.trim());
    }
    throw ForgeRequestFailed(
      result.stderr.trim().isEmpty ? 'gh command failed' : result.stderr.trim(),
    );
  }

  CreateReviewFailure _mapCreateFailure(ProcessRunOutput result) {
    if (_looksLikeMissingCli(result)) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.cliMissing,
        message: 'The gh CLI was not found on PATH.',
      );
    }
    final stderr = result.stderr.toLowerCase();
    if (stderr.contains('not logged') ||
        stderr.contains('authentication') ||
        stderr.contains('gh auth login')) {
      return CreateReviewFailure(
        code: CreateReviewErrorCode.notAuthenticated,
        message: 'Run `gh auth login` to authenticate.',
      );
    }
    if (stderr.contains('already exists') ||
        stderr.contains('a pull request for branch')) {
      return CreateReviewFailure(
        code: CreateReviewErrorCode.alreadyExists,
        message: 'A pull request already exists for this branch.',
      );
    }
    return CreateReviewFailure(
      code: CreateReviewErrorCode.unknown,
      message: result.stderr.trim().isEmpty
          ? 'gh pr create failed.'
          : result.stderr.trim(),
    );
  }

  HostedReview _mapReview(Map<String, Object?> json) {
    final state = (json['state'] as String? ?? 'OPEN').toUpperCase();
    final isDraft = json['isDraft'] as bool? ?? false;
    final author = json['author'];
    return HostedReview(
      provider: GitHostingProvider.github,
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      state: _mapState(state, isDraft),
      url: json['url'] as String? ?? '',
      author: author is Map<String, Object?> ? author['login'] as String? : null,
      baseBranch: json['baseRefName'] as String?,
      headBranch: json['headRefName'] as String?,
      headSha: json['headRefOid'] as String?,
      mergeable: _mapMergeable(json['mergeable'] as String?),
    );
  }

  HostedReviewState _mapState(String state, bool isDraft) {
    return switch (state) {
      'MERGED' => HostedReviewState.merged,
      'CLOSED' => HostedReviewState.closed,
      _ => isDraft ? HostedReviewState.draft : HostedReviewState.open,
    };
  }

  HostedReviewMergeable _mapMergeable(String? value) {
    return switch (value?.toUpperCase()) {
      'MERGEABLE' => HostedReviewMergeable.mergeable,
      'CONFLICTING' => HostedReviewMergeable.conflicting,
      _ => HostedReviewMergeable.unknown,
    };
  }

  ReviewCheck _mapCheck(Map<String, Object?> json) {
    final bucket = (json['bucket'] as String? ?? '').toLowerCase();
    final conclusion = switch (bucket) {
      'pass' => ReviewCheckConclusion.success,
      'fail' => ReviewCheckConclusion.failure,
      'cancel' => ReviewCheckConclusion.cancelled,
      'skipping' => ReviewCheckConclusion.skipped,
      _ => ReviewCheckConclusion.pending,
    };
    final status = bucket == 'pending'
        ? ReviewCheckStatus.inProgress
        : ReviewCheckStatus.completed;
    final link = json['link'] as String?;
    return ReviewCheck(
      name: json['name'] as String? ?? 'check',
      status: status,
      conclusion: conclusion,
      url: link != null && link.isNotEmpty ? link : null,
    );
  }

  Object? _decodeJson(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final decoded = _tryDecode(trimmed);
    if (decoded == null) {
      throw ForgeRequestFailed('Unexpected gh output: $trimmed');
    }
    return decoded;
  }

  Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeMissingCli(ProcessRunOutput result) {
    if (result.exitCode != 127) {
      final combined = '${result.stdout} ${result.stderr}'.toLowerCase();
      return combined.contains('command not found') ||
          combined.contains('is not recognized') ||
          combined.contains('no such file');
    }
    return true;
  }

  bool _mentionsNoChecks(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('no checks') || lower.contains('no check runs');
  }

  bool _mentionsNotFound(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('no pull requests found') ||
        lower.contains('not found') ||
        lower.contains('could not resolve');
  }

  int? _pullNumberFromUrl(String output) {
    final url = _firstUrl(output);
    if (url == null) {
      return null;
    }
    final match = RegExp(r'/pull/(\d+)').firstMatch(url);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  String? _firstUrl(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('http')) {
        return trimmed;
      }
    }
    return null;
  }
}
