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

/// [ForgeProvider] for Azure DevOps, wrapping the official `az` CLI (with the
/// `azure-devops` extension). Authentication relies on `az login`. Checks are
/// derived from PR policy evaluations.
class AzureDevOpsForgeProvider implements ForgeProvider {
  const AzureDevOpsForgeProvider(this._processRunner);

  final ProcessRunner _processRunner;

  @override
  GitHostingProvider get id => GitHostingProvider.azureDevops;

  @override
  bool get supportsReviewCreation => true;

  /// The organization base URL. Legacy `*.visualstudio.com` hosts embed the org
  /// in the subdomain; modern hosts use `dev.azure.com/{org}`.
  String _orgUrl(GitRemoteIdentity identity) {
    if (identity.host.contains('visualstudio.com')) {
      return 'https://${identity.owner}.visualstudio.com';
    }
    return 'https://dev.azure.com/${identity.owner}';
  }

  String _webUrl(GitRemoteIdentity identity, int number) {
    final project = identity.project ?? '';
    return '${_orgUrl(identity)}/$project/_git/${identity.repo}/pullrequest/$number';
  }

  @override
  Future<ForgeAuthStatus> checkAuth({
    required GitRemoteIdentity identity,
  }) async {
    try {
      final result = await _processRunner.run('az', const <String>[
        'account',
        'show',
        '--output',
        'json',
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
    final output = await _run(<String>[
      'repos',
      'pr',
      'list',
      '--organization',
      _orgUrl(identity),
      '--project',
      identity.project ?? '',
      '--repository',
      identity.repo,
      '--source-branch',
      branch,
      '--status',
      'active',
      '--output',
      'json',
    ], repoPath);
    final decoded = _decodeJson(output);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }
    return _mapReview(identity, decoded.first as Map<String, Object?>);
  }

  @override
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final output = await _run(
      <String>[
        'repos',
        'pr',
        'show',
        '--id',
        '$number',
        '--organization',
        _orgUrl(identity),
        '--output',
        'json',
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
    return _mapReview(identity, decoded);
  }

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final output = await _run(
      <String>[
        'repos',
        'pr',
        'policy',
        'list',
        '--id',
        '$number',
        '--organization',
        _orgUrl(identity),
        '--output',
        'json',
      ],
      repoPath,
      allowNotFound: true,
    );
    final decoded = _decodeJson(output);
    if (decoded is! List) {
      return const <ReviewCheck>[];
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
      result = await _processRunner.run('az', <String>[
        'repos',
        'pr',
        'create',
        '--organization',
        _orgUrl(identity),
        '--project',
        identity.project ?? '',
        '--repository',
        identity.repo,
        '--source-branch',
        input.headBranch,
        '--target-branch',
        input.baseBranch,
        '--title',
        input.title,
        '--description',
        input.body ?? '',
        if (input.draft) ...<String>['--draft', 'true'],
        '--output',
        'json',
      ], workingDirectory: repoPath);
    } catch (_) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.cliMissing,
        message: 'The az CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return _mapCreateFailure(result);
    }
    final decoded = _tryDecode(result.stdout.trim());
    if (decoded is Map<String, Object?>) {
      return CreateReviewSuccess(_mapReview(identity, decoded));
    }
    return const CreateReviewFailure(
      code: CreateReviewErrorCode.unknown,
      message: 'The pull request was created but could not be read back.',
    );
  }

  Future<String?> _run(
    List<String> arguments,
    String repoPath, {
    bool allowNotFound = false,
  }) async {
    ProcessRunOutput result;
    try {
      result = await _processRunner.run(
        'az',
        arguments,
        workingDirectory: repoPath,
      );
    } catch (_) {
      throw const ForgeCliMissing('az not found');
    }
    if (result.exitCode == 0) {
      return result.stdout;
    }
    if (_looksLikeMissingCli(result)) {
      throw const ForgeCliMissing(
        'The az CLI or azure-devops extension is not installed.',
      );
    }
    if (allowNotFound && _mentionsNotFound(result.stderr)) {
      return null;
    }
    _throwClassified(result);
  }

  Never _throwClassified(ProcessRunOutput result) {
    final stderr = result.stderr.toLowerCase();
    if (stderr.contains('az login') || stderr.contains('not logged in')) {
      throw ForgeNotAuthenticated(result.stderr.trim());
    }
    throw ForgeRequestFailed(
      result.stderr.trim().isEmpty ? 'az command failed' : result.stderr.trim(),
    );
  }

  CreateReviewFailure _mapCreateFailure(ProcessRunOutput result) {
    if (_looksLikeMissingCli(result)) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.cliMissing,
        message: 'The az CLI or azure-devops extension is not installed.',
      );
    }
    final stderr = result.stderr.toLowerCase();
    if (stderr.contains('az login') || stderr.contains('not logged in')) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.notAuthenticated,
        message: 'Run `az login` to authenticate.',
      );
    }
    if (stderr.contains('already exists') ||
        stderr.contains('active pull request')) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.alreadyExists,
        message: 'A pull request already exists for this branch.',
      );
    }
    return CreateReviewFailure(
      code: CreateReviewErrorCode.unknown,
      message: result.stderr.trim().isEmpty
          ? 'az repos pr create failed.'
          : result.stderr.trim(),
    );
  }

  HostedReview _mapReview(
    GitRemoteIdentity identity,
    Map<String, Object?> json,
  ) {
    final number = (json['pullRequestId'] as num?)?.toInt() ?? 0;
    final status = (json['status'] as String? ?? 'active').toLowerCase();
    final isDraft = json['isDraft'] as bool? ?? false;
    final createdBy = json['createdBy'];
    final lastMerge = json['lastMergeSourceCommit'];
    return HostedReview(
      provider: GitHostingProvider.azureDevops,
      number: number,
      title: json['title'] as String? ?? '',
      state: _mapState(status, isDraft),
      url: _webUrl(identity, number),
      author: createdBy is Map<String, Object?>
          ? createdBy['displayName'] as String?
          : null,
      baseBranch: _shortRef(json['targetRefName'] as String?),
      headBranch: _shortRef(json['sourceRefName'] as String?),
      headSha: lastMerge is Map<String, Object?>
          ? lastMerge['commitId'] as String?
          : null,
      mergeable: _mapMergeable(json['mergeStatus'] as String?),
    );
  }

  HostedReviewState _mapState(String status, bool isDraft) {
    return switch (status) {
      'completed' => HostedReviewState.merged,
      'abandoned' => HostedReviewState.closed,
      _ => isDraft ? HostedReviewState.draft : HostedReviewState.open,
    };
  }

  HostedReviewMergeable _mapMergeable(String? value) {
    return switch (value?.toLowerCase()) {
      'succeeded' => HostedReviewMergeable.mergeable,
      'conflicts' => HostedReviewMergeable.conflicting,
      _ => HostedReviewMergeable.unknown,
    };
  }

  ReviewCheck _mapCheck(Map<String, Object?> json) {
    final status = (json['status'] as String? ?? '').toLowerCase();
    final conclusion = switch (status) {
      'approved' => ReviewCheckConclusion.success,
      'rejected' => ReviewCheckConclusion.failure,
      'notapplicable' => ReviewCheckConclusion.skipped,
      'queued' || 'running' => ReviewCheckConclusion.pending,
      _ => ReviewCheckConclusion.neutral,
    };
    final checkStatus = (status == 'queued' || status == 'running')
        ? ReviewCheckStatus.inProgress
        : ReviewCheckStatus.completed;
    return ReviewCheck(
      name: _policyName(json),
      status: checkStatus,
      conclusion: conclusion,
    );
  }

  String _policyName(Map<String, Object?> json) {
    final configuration = json['configuration'];
    if (configuration is Map<String, Object?>) {
      final type = configuration['type'];
      if (type is Map<String, Object?>) {
        final displayName = type['displayName'];
        if (displayName is String && displayName.isNotEmpty) {
          return displayName;
        }
      }
    }
    return 'Policy';
  }

  String? _shortRef(String? ref) {
    if (ref == null) {
      return null;
    }
    const prefix = 'refs/heads/';
    return ref.startsWith(prefix) ? ref.substring(prefix.length) : ref;
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
      throw ForgeRequestFailed('Unexpected az output: $trimmed');
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
    if (result.exitCode == 127) {
      return true;
    }
    final combined = '${result.stdout} ${result.stderr}'.toLowerCase();
    return combined.contains('command not found') ||
        combined.contains('is not recognized') ||
        combined.contains('no such file') ||
        combined.contains("'repos' is misspelled") ||
        combined.contains('az extension add');
  }

  bool _mentionsNotFound(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('does not exist') ||
        lower.contains('not found') ||
        lower.contains('tf401180');
  }
}
