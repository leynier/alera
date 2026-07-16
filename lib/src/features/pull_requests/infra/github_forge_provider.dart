import 'dart:convert';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/infra/github_cli_failures.dart';
import 'package:alera/src/features/pull_requests/infra/github_review_mappers.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

part 'github_review_actions.dart';
part 'github_review_comments.dart';

/// [ForgeProvider] for GitHub, wrapping the official `gh` CLI. Authentication
/// relies on the user being logged in via `gh auth login`. Follows the
/// `GitHubStarService` pattern: constructor-injected [ProcessRunner], typed
/// errors instead of leaked stderr.
class GitHubForgeProvider
    with _GitHubReviewActions, _GitHubReviewComments
    implements ForgeProvider {
  const GitHubForgeProvider(this._processRunner);

  final ProcessRunner _processRunner;

  static const List<String> _reviewJsonFields = <String>[
    'number',
    'title',
    'state',
    'url',
    'createdAt',
    'isDraft',
    'mergeable',
    'headRefName',
    'baseRefName',
    'headRefOid',
    'author',
  ];

  static const List<String> _checkJsonFields = <String>[
    'name',
    'state',
    'bucket',
    'link',
  ];

  static const List<String> _checkDetailJsonFields = <String>[
    ..._checkJsonFields,
    'description',
    'event',
    'workflow',
    'startedAt',
    'completedAt',
  ];

  @override
  GitHostingProvider get id => GitHostingProvider.github;

  @override
  bool get supportsReviewCreation => true;

  @override
  bool get supportsReviewComments => true;

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
      if (ghLooksLikeMissingCli(result)) {
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
    final output = await _run(<String>[
      'pr',
      'list',
      '--repo',
      _repoSlug(identity),
      '--head',
      branch,
      '--state',
      'open',
      '--limit',
      '100',
      '--json',
      _reviewJsonFields.join(','),
    ], repoPath);
    final decoded = _decodeJson(output);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }
    return pickNewestHostedReview(
      decoded.whereType<Map>().map(
        (item) => mapGitHubReview(Map<String, Object?>.from(item)),
      ),
    );
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
    return mapGitHubReview(decoded);
  }

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final entries = await _fetchCheckEntries(
      identity,
      repoPath,
      number,
      _checkJsonFields,
    );
    return <ReviewCheck>[for (final entry in entries) mapGitHubCheck(entry)];
  }

  @override
  Future<ReviewCheckDetails?> getCheckDetails({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCheck check,
  }) async {
    final entries = await _fetchCheckEntries(
      identity,
      repoPath,
      number,
      _checkDetailJsonFields,
    );
    Map<String, Object?>? match;
    for (final entry in entries) {
      if ((entry['name'] as String?) != check.name) {
        continue;
      }
      match ??= entry;
      if (check.url != null && (entry['link'] as String?) == check.url) {
        match = entry;
        break;
      }
    }
    if (match == null) {
      return null;
    }
    return mapGitHubCheckDetails(match);
  }

  /// Fetches the raw `gh pr checks` entries for review [number]. `gh pr
  /// checks` exits non-zero when checks are pending or failing, so the exit
  /// code is not a success signal — parse stdout regardless and only treat a
  /// genuine "no checks" as an empty list.
  Future<List<Map<String, Object?>>> _fetchCheckEntries(
    GitRemoteIdentity identity,
    String repoPath,
    int number,
    List<String> fields,
  ) async {
    ProcessRunOutput result;
    try {
      result = await _processRunner.run('gh', <String>[
        'pr',
        'checks',
        '$number',
        '--repo',
        _repoSlug(identity),
        '--json',
        fields.join(','),
      ], workingDirectory: repoPath);
    } catch (_) {
      throw const ForgeCliMissing('gh not found');
    }
    if (ghLooksLikeMissingCli(result)) {
      throw const ForgeCliMissing('gh not found');
    }
    final stdout = result.stdout.trim();
    if (stdout.isEmpty) {
      if (_mentionsNoChecks(result.stderr)) {
        return const <Map<String, Object?>>[];
      }
      _throwClassified(result);
    }
    final decoded = _tryDecode(stdout);
    if (decoded is! List) {
      if (_mentionsNoChecks(result.stderr)) {
        return const <Map<String, Object?>>[];
      }
      throw ForgeRequestFailed('Unexpected gh pr checks output: $stdout');
    }
    return <Map<String, Object?>>[
      for (final entry in decoded)
        if (entry is Map<String, Object?>) entry,
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
      return mapGitHubCreateFailure(result);
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
          state: input.draft ? HostedReviewState.draft : HostedReviewState.open,
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

  @override
  Future<UpdateReviewResult> updateReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required UpdateReviewInput input,
  }) async {
    ProcessRunOutput result;
    try {
      result = await _processRunner.run('gh', <String>[
        'pr',
        'edit',
        '$number',
        '--repo',
        _repoSlug(identity),
        if (input.title != null) ...<String>['--title', input.title!],
        if (input.baseBranch != null) ...<String>['--base', input.baseBranch!],
      ], workingDirectory: repoPath);
    } catch (_) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.cliMissing,
        message: 'The gh CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return mapGitHubUpdateFailure(result);
    }
    final review = await getReviewByNumber(
      identity: identity,
      repoPath: repoPath,
      number: number,
    );
    if (review == null) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.unknown,
        message: 'The pull request was updated but could not be read back.',
      );
    }
    return UpdateReviewSuccess(review);
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
    if (ghLooksLikeMissingCli(result)) {
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
