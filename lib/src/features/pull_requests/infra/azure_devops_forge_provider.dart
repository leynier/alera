import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/application/repository_web_url.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_cli_failures.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_review_mappers.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

part 'azure_devops_review_actions.dart';
part 'azure_devops_review_comments.dart';

/// [ForgeProvider] for Azure DevOps, wrapping the official `az` CLI (with the
/// `azure-devops` extension). Authentication relies on `az login`. Checks are
/// derived from PR policy evaluations.
class const AzureDevOpsForgeProvider(final ProcessRunner _processRunner)
    with _AzureDevOpsReviewActions, _AzureDevOpsReviewComments
    implements ForgeProvider {
  @override
  GitHostingProvider get id => GitHostingProvider.azureDevops;

  @override
  bool get supportsReviewCreation => true;

  @override
  bool get supportsReviewCommentEditing => true;

  @override
  bool get supportsReviewComments => true;

  @visibleForTesting
  static String commentThreadBodyJson(String body) {
    return jsonEncode(<String, Object>{
      'comments': <Object>[
        <String, Object>{
          'parentCommentId': 0,
          'content': body,
          'commentType': 1,
        },
      ],
      'status': 1,
    });
  }

  @visibleForTesting
  static String commentBodyJson(String body) {
    return jsonEncode(<String, String>{'content': body});
  }

  /// PATCH body for retargeting a pull request via `az devops invoke`.
  @visibleForTesting
  static String retargetBodyJson(String branch) {
    final ref = branch.startsWith('refs/') ? branch : 'refs/heads/$branch';
    return jsonEncode(<String, String>{'targetRefName': ref});
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
      if (azLooksLikeMissingCli(result)) {
        return ForgeAuthStatus.cliMissing;
      }
      return ForgeAuthStatus.notAuthenticated;
    } catch (_) {
      return ForgeAuthStatus.cliMissing;
    }
  }

  @override
  Future<UpdateReviewResult> updateReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required UpdateReviewInput input,
  }) async {
    final project = identity.project;
    if (input.baseBranch != null && (project == null || project.isEmpty)) {
      return const UpdateReviewFailure(
        code: .blocked,
        message:
            'The Azure DevOps project could not be determined from the '
            'remote.',
      );
    }
    if (input.title != null) {
      final failure = await _updateTitle(
        identity,
        repoPath,
        number,
        input.title!,
      );
      if (failure != null) {
        return failure;
      }
    }
    if (input.baseBranch != null) {
      final failure = await _retarget(
        identity,
        repoPath,
        number,
        input.baseBranch!,
        titleUpdated: input.title != null,
      );
      if (failure != null) {
        return failure;
      }
    }
    final review = await getReviewByNumber(
      identity: identity,
      repoPath: repoPath,
      number: number,
    );
    if (review == null) {
      return const UpdateReviewFailure(
        code: .unknown,
        message: 'The pull request was updated but could not be read back.',
      );
    }
    return UpdateReviewSuccess(review);
  }

  Future<UpdateReviewFailure?> _updateTitle(
    GitRemoteIdentity identity,
    String repoPath,
    int number,
    String title,
  ) async {
    ProcessRunOutput result;
    try {
      result = await _processRunner.run('az', <String>[
        'repos',
        'pr',
        'update',
        '--id',
        '$number',
        '--organization',
        azureOrgUrl(identity),
        '--title',
        title,
        '--output',
        'json',
      ], workingDirectory: repoPath);
    } catch (_) {
      return const UpdateReviewFailure(
        code: .cliMissing,
        message: 'The az CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return mapAzureUpdateFailure(result);
    }
    return null;
  }

  /// `az repos pr update` cannot change the target branch, so retargeting
  /// PATCHes the pull request through the azure-devops extension's generic
  /// invoker, which shares its authentication (including `az devops login`
  /// PATs) with every other call in this provider.
  Future<UpdateReviewFailure?> _retarget(
    GitRemoteIdentity identity,
    String repoPath,
    int number,
    String baseBranch, {
    required bool titleUpdated,
  }) async {
    UpdateReviewFailure? annotate(UpdateReviewFailure failure) {
      if (!titleUpdated) {
        return failure;
      }
      return UpdateReviewFailure(
        code: failure.code,
        message: '${failure.message} (the title may already have been updated)',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('alera-pr-retarget');
    try {
      final bodyFile = File(p.join(tempDir.path, 'body.json'));
      await bodyFile.writeAsString(retargetBodyJson(baseBranch));
      ProcessRunOutput result;
      try {
        result = await _processRunner.run('az', <String>[
          'devops',
          'invoke',
          '--area',
          'git',
          '--resource',
          'pullrequests',
          '--route-parameters',
          'project=${identity.project}',
          'repositoryId=${identity.repo}',
          'pullRequestId=$number',
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
        ], workingDirectory: repoPath);
      } catch (_) {
        return annotate(
          const UpdateReviewFailure(
            code: .cliMissing,
            message: 'The az CLI was not found on PATH.',
          ),
        );
      }
      if (result.exitCode != 0) {
        return annotate(mapAzureUpdateFailure(result));
      }
      return null;
    } finally {
      await tempDir.delete(recursive: true);
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
      azureOrgUrl(identity),
      '--project',
      identity.project ?? '',
      '--repository',
      identity.repo,
      '--source-branch',
      branch,
      '--status',
      'active',
      '--top',
      '100',
      '--output',
      'json',
    ], repoPath);
    final decoded = _decodeJson(output);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }
    return pickNewestHostedReview(
      decoded.whereType<Map>().map(
        (item) => mapAzureReview(identity, Map<String, Object?>.from(item)),
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
        'repos',
        'pr',
        'show',
        '--id',
        '$number',
        '--organization',
        azureOrgUrl(identity),
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
    return mapAzureReview(identity, decoded);
  }

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final entries = await _fetchPolicyEvaluations(identity, repoPath, number);
    return <ReviewCheck>[for (final entry in entries) mapAzureCheck(entry)];
  }

  @override
  Future<ReviewCheckDetails?> getCheckDetails({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCheck check,
  }) async {
    final entries = await _fetchPolicyEvaluations(identity, repoPath, number);
    for (final entry in entries) {
      if (azurePolicyName(entry) == check.name) {
        return mapAzureCheckDetails(identity, entry);
      }
    }
    return null;
  }

  Future<List<Map<String, Object?>>> _fetchPolicyEvaluations(
    GitRemoteIdentity identity,
    String repoPath,
    int number,
  ) async {
    final output = await _run(
      <String>[
        'repos',
        'pr',
        'policy',
        'list',
        '--id',
        '$number',
        '--organization',
        azureOrgUrl(identity),
        '--output',
        'json',
      ],
      repoPath,
      allowNotFound: true,
    );
    final decoded = _decodeJson(output);
    if (decoded is! List) {
      return const <Map<String, Object?>>[];
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
      result = await _processRunner.run('az', <String>[
        'repos',
        'pr',
        'create',
        '--organization',
        azureOrgUrl(identity),
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
        code: .cliMissing,
        message: 'The az CLI was not found on PATH.',
      );
    }
    if (result.exitCode != 0) {
      return mapAzureCreateFailure(result);
    }
    final decoded = _tryDecode(result.stdout.trim());
    if (decoded is Map<String, Object?>) {
      return CreateReviewSuccess(mapAzureReview(identity, decoded));
    }
    return const CreateReviewFailure(
      code: .unknown,
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
    if (azLooksLikeMissingCli(result)) {
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

  bool _mentionsNotFound(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('does not exist') ||
        lower.contains('not found') ||
        lower.contains('tf401180');
  }
}
