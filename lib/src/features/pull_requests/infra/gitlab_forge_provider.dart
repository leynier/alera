import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/infra/gitlab_review_mappers.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

part 'gitlab_review_actions.dart';
part 'gitlab_review_comments.dart';

/// GitLab forge integration backed by the official `glab` CLI.
class GitLabForgeProvider
    with _GitLabReviewActions, _GitLabReviewComments
    implements ForgeProvider {
  const GitLabForgeProvider(this._processRunner);

  final ProcessRunner _processRunner;

  @override
  GitHostingProvider get id => GitHostingProvider.gitlab;

  @override
  bool get supportsReviewCreation => true;

  String _repoUrl(GitRemoteIdentity identity) =>
      'https://${identity.host}/${identity.owner}/${identity.repo}';

  String _projectEndpoint(GitRemoteIdentity identity) {
    final path = Uri.encodeComponent('${identity.owner}/${identity.repo}');
    return 'projects/$path';
  }

  @override
  Future<ForgeAuthStatus> checkAuth({
    required GitRemoteIdentity identity,
  }) async {
    try {
      final result = await _processRunner.run('glab', <String>[
        'auth',
        'status',
        '--hostname',
        identity.host,
      ]);
      if (result.exitCode == 0) {
        return ForgeAuthStatus.authenticated;
      }
      return _looksMissing(result)
          ? ForgeAuthStatus.cliMissing
          : ForgeAuthStatus.notAuthenticated;
    } on ProcessException {
      return ForgeAuthStatus.cliMissing;
    }
  }

  @override
  Future<HostedReview?> getReviewForBranch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String branch,
  }) async {
    final endpoint =
        '${_projectEndpoint(identity)}/merge_requests'
        '?state=opened&source_branch=${Uri.encodeQueryComponent(branch)}'
        '&per_page=100';
    final decoded = _decodeNdjson(
      await _api(identity, repoPath, endpoint, paginate: true),
    );
    return pickNewestHostedReview(
      decoded.whereType<Map>().map(
        (item) => mapGitLabReview(Map<String, Object?>.from(item)),
      ),
    );
  }

  @override
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final output = await _api(
      identity,
      repoPath,
      '${_projectEndpoint(identity)}/merge_requests/$number',
      allowNotFound: true,
    );
    if (output == null) {
      return null;
    }
    final decoded = _decodeJson(output);
    return decoded is Map<String, Object?> ? mapGitLabReview(decoded) : null;
  }

  Future<Map<String, Object?>?> _headPipeline(
    GitRemoteIdentity identity,
    String repoPath,
    int number,
  ) async {
    final output = await _api(
      identity,
      repoPath,
      '${_projectEndpoint(identity)}/merge_requests/$number',
    );
    final decoded = _decodeJson(output);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final pipeline = decoded['head_pipeline'];
    return pipeline is Map ? Map<String, Object?>.from(pipeline) : null;
  }

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final pipeline = await _headPipeline(identity, repoPath, number);
    return pipeline == null
        ? const <ReviewCheck>[]
        : <ReviewCheck>[mapGitLabPipeline(pipeline)];
  }

  @override
  Future<ReviewCheckDetails?> getCheckDetails({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCheck check,
  }) async {
    final pipeline = await _headPipeline(identity, repoPath, number);
    if (pipeline == null) {
      return null;
    }
    final mapped = mapGitLabPipeline(pipeline);
    if (mapped.name != check.name ||
        (check.url != null && mapped.url != check.url)) {
      return null;
    }
    final id = (pipeline['id'] as num?)?.toInt();
    if (id == null) {
      return mapGitLabPipelineDetails(pipeline);
    }
    final output = await _api(
      identity,
      repoPath,
      '${_projectEndpoint(identity)}/pipelines/$id',
    );
    final details = _decodeJson(output);
    return details is Map<String, Object?>
        ? mapGitLabPipelineDetails(details)
        : null;
  }

  @override
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  }) async {
    final result = await _runResult(<String>[
      'mr',
      'create',
      '--repo',
      _repoUrl(identity),
      '--source-branch',
      input.headBranch,
      '--target-branch',
      input.baseBranch,
      '--title',
      input.title,
      '--description',
      input.body ?? '',
      if (input.draft) '--draft',
      '--yes',
    ], repoPath);
    if (result == null) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.cliMissing,
        message: 'The glab CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return _mapCreateFailure(result);
    }
    final number = _mergeRequestNumber(result.stdout);
    final review = number != null
        ? await getReviewByNumber(
            identity: identity,
            repoPath: repoPath,
            number: number,
          )
        : await getReviewForBranch(
            identity: identity,
            repoPath: repoPath,
            branch: input.headBranch,
          );
    if (review != null) {
      return CreateReviewSuccess(review);
    }
    return const CreateReviewFailure(
      code: CreateReviewErrorCode.unknown,
      message: 'The merge request was created but could not be read back.',
    );
  }

  @override
  Future<UpdateReviewResult> updateReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required UpdateReviewInput input,
  }) async {
    final result = await _runResult(<String>[
      'mr',
      'update',
      '$number',
      '--repo',
      _repoUrl(identity),
      if (input.title != null) ...<String>['--title', input.title!],
      if (input.baseBranch != null) ...<String>[
        '--target-branch',
        input.baseBranch!,
      ],
      '--yes',
    ], repoPath);
    if (result == null) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.cliMissing,
        message: 'The glab CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return _mapUpdateFailure(result);
    }
    final review = await getReviewByNumber(
      identity: identity,
      repoPath: repoPath,
      number: number,
    );
    return review == null
        ? const UpdateReviewFailure(
            code: UpdateReviewErrorCode.unknown,
            message:
                'The merge request was updated but could not be read back.',
          )
        : UpdateReviewSuccess(review);
  }

  Future<String?> _api(
    GitRemoteIdentity identity,
    String repoPath,
    String endpoint, {
    String? method,
    List<String> fields = const <String>[],
    bool allowNotFound = false,
    bool paginate = false,
  }) {
    final requiresRepositoryOverride = identity.host.contains(':');
    return _run(
      <String>[
        'api',
        endpoint,
        // `glab api --hostname` rejects authorities containing a port.
        if (!requiresRepositoryOverride) ...<String>[
          '--hostname',
          identity.host,
        ],
        if (paginate) ...<String>['--paginate', '--output', 'ndjson'],
        if (method != null) ...<String>['--method', method],
        for (final field in fields) ...<String>['--raw-field', field],
      ],
      repoPath,
      allowNotFound: allowNotFound,
      environment: requiresRepositoryOverride
          ? <String, String>{'GITLAB_REPO': _repoUrl(identity)}
          : null,
    );
  }

  Future<ProcessRunOutput?> _runResult(
    List<String> arguments,
    String repoPath, {
    Map<String, String>? environment,
  }) async {
    try {
      return await _processRunner.run(
        'glab',
        arguments,
        workingDirectory: repoPath,
        environment: environment,
      );
    } on ProcessException {
      return null;
    }
  }

  Future<String?> _run(
    List<String> arguments,
    String repoPath, {
    bool allowNotFound = false,
    Map<String, String>? environment,
  }) async {
    final result = await _runResult(
      arguments,
      repoPath,
      environment: environment,
    );
    if (result == null) {
      throw const ForgeCliMissing('glab not found');
    }
    if (result.exitCode == 0) {
      return result.stdout;
    }
    if (_looksMissing(result)) {
      throw const ForgeCliMissing('glab not found');
    }
    final lower = result.stderr.toLowerCase();
    if (allowNotFound &&
        (lower.contains('404') || lower.contains('not found'))) {
      return null;
    }
    if (_looksUnauthenticated(result.stderr)) {
      throw ForgeNotAuthenticated(result.stderr.trim());
    }
    throw ForgeRequestFailed(
      result.stderr.trim().isEmpty
          ? 'glab command failed'
          : result.stderr.trim(),
    );
  }

  Object? _decodeJson(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      throw ForgeRequestFailed('Unexpected glab output: $trimmed');
    }
  }

  List<Object?> _decodeNdjson(String? raw) {
    final records = <Object?>[];
    try {
      for (final line in const LineSplitter().convert(raw?.trim() ?? '')) {
        if (line.trim().isNotEmpty) {
          records.add(jsonDecode(line));
        }
      }
      return records;
    } catch (_) {
      throw ForgeRequestFailed('Unexpected glab NDJSON output: ${raw?.trim()}');
    }
  }

  bool _looksMissing(ProcessRunOutput result) {
    if (result.exitCode == 127) {
      return true;
    }
    final stderr = result.stderr.toLowerCase();
    return stderr.contains('command not found') ||
        stderr.contains('is not recognized') ||
        stderr.contains('no such file');
  }

  bool _looksUnauthenticated(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('not logged') ||
        lower.contains('unauthorized') ||
        lower.contains('authentication') ||
        lower.contains('glab auth login');
  }

  CreateReviewFailure _mapCreateFailure(ProcessRunOutput result) {
    if (_looksMissing(result)) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.cliMissing,
        message: 'The glab CLI was not found on PATH.',
      );
    }
    if (_looksUnauthenticated(result.stderr)) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.notAuthenticated,
        message: 'Run `glab auth login` to authenticate.',
      );
    }
    final lower = result.stderr.toLowerCase();
    if (lower.contains('already exists') ||
        lower.contains('another open merge request')) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.alreadyExists,
        message: 'A merge request already exists for this branch.',
      );
    }
    return CreateReviewFailure(
      code: CreateReviewErrorCode.unknown,
      message: result.stderr.trim().isEmpty
          ? 'glab mr create failed.'
          : result.stderr.trim(),
    );
  }

  UpdateReviewFailure _mapUpdateFailure(ProcessRunOutput result) {
    if (_looksMissing(result)) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.cliMissing,
        message: 'The glab CLI was not found on PATH.',
      );
    }
    if (_looksUnauthenticated(result.stderr)) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.notAuthenticated,
        message: 'Run `glab auth login` to authenticate.',
      );
    }
    return UpdateReviewFailure(
      code: UpdateReviewErrorCode.unknown,
      message: result.stderr.trim().isEmpty
          ? 'glab mr update failed.'
          : result.stderr.trim(),
    );
  }

  int? _mergeRequestNumber(String output) {
    final match = RegExp(r'/-/merge_requests/(\d+)').firstMatch(output);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
