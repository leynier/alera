import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_forge_provider.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _identity = GitRemoteIdentity(
  provider: GitHostingProvider.azureDevops,
  host: 'dev.azure.com',
  owner: 'myorg',
  repo: 'myrepo',
  project: 'myproject',
);

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  group('AzureDevOpsForgeProvider.getReviewForBranch', () {
    test('builds az repos pr list argv and maps the newest PR', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"pullRequestId":42,"title":"feat: older","status":"active","creationDate":"2026-07-10T00:00:00Z","isDraft":false,"sourceRefName":"refs/heads/feature","targetRefName":"refs/heads/main","mergeStatus":"succeeded","createdBy":{"displayName":"Ley"},"lastMergeSourceCommit":{"commitId":"abc"}},
 {"pullRequestId":43,"title":"feat: newest","status":"active","creationDate":"2026-07-11T00:00:00Z","isDraft":false,"sourceRefName":"refs/heads/feature","targetRefName":"refs/heads/main","mergeStatus":"succeeded","createdBy":{"displayName":"Ley"},"lastMergeSourceCommit":{"commitId":"def"},"lastMergeTargetCommit":{"commitId":"base-def"},"sourceRepository":{"remoteUrl":"https://dev.azure.com/myorg/fork/_git/myrepo"}}]
'''),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final review = await provider.getReviewForBranch(
        identity: _identity,
        repoPath: '/repo',
        branch: 'feature',
      );

      final call = runner.calls.single;
      expect(call.executable, 'az');
      expect(call.arguments.sublist(0, 3), <String>['repos', 'pr', 'list']);
      expect(call.optionValue('organization'), 'https://dev.azure.com/myorg');
      expect(call.optionValue('project'), 'myproject');
      expect(call.optionValue('repository'), 'myrepo');
      expect(call.optionValue('source-branch'), 'feature');
      expect(call.optionValue('top'), '100');
      expect(review, isNotNull);
      expect(review!.number, 43);
      expect(review.title, 'feat: newest');
      expect(review.createdAt, DateTime.parse('2026-07-11T00:00:00Z'));
      expect(review.state, HostedReviewState.open);
      expect(review.mergeable, HostedReviewMergeable.mergeable);
      expect(review.headBranch, 'feature');
      expect(review.baseBranch, 'main');
      expect(review.comparisonBaseSha, 'base-def');
      expect(
        review.headRepositoryUrl,
        'https://dev.azure.com/myorg/fork/_git/myrepo',
      );
      expect(
        review.url,
        'https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/43',
      );
    });

    test('returns null on an empty list', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('[]')]);
      final provider = AzureDevOpsForgeProvider(runner);
      final review = await provider.getReviewForBranch(
        identity: _identity,
        repoPath: '/repo',
        branch: 'feature',
      );
      expect(review, isNull);
    });

    test('uses the visualstudio.com org URL for legacy hosts', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('[]')]);
      final provider = AzureDevOpsForgeProvider(runner);
      await provider.getReviewForBranch(
        identity: const GitRemoteIdentity(
          provider: GitHostingProvider.azureDevops,
          host: 'myorg.visualstudio.com',
          owner: 'myorg',
          repo: 'myrepo',
          project: 'myproject',
        ),
        repoPath: '/repo',
        branch: 'x',
      );
      expect(
        runner.calls.single.optionValue('organization'),
        'https://myorg.visualstudio.com',
      );
    });
  });

  group('AzureDevOpsForgeProvider.getChecks', () {
    test('maps policy evaluations to checks', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"status":"approved","configuration":{"type":{"displayName":"Build"}}},
 {"status":"rejected","configuration":{"type":{"displayName":"Required reviewers"}}},
 {"status":"running","configuration":{"type":{"displayName":"Status"}}}]
'''),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final checks = await provider.getChecks(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
      );
      expect(checks, hasLength(3));
      expect(checks[0].name, 'Build');
      expect(checks[0].conclusion, ReviewCheckConclusion.success);
      expect(checks[1].conclusion, ReviewCheckConclusion.failure);
      expect(checks[2].conclusion, ReviewCheckConclusion.pending);
      expect(checks[2].status, ReviewCheckStatus.inProgress);
    });
  });

  group('AzureDevOpsForgeProvider.getCheckDetails', () {
    const check = ReviewCheck(
      name: 'Build',
      status: ReviewCheckStatus.inProgress,
      conclusion: ReviewCheckConclusion.pending,
    );

    test('maps policy evaluation metadata and build url', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"status":"running","startedDate":"2026-07-15T10:00:00Z","completedDate":"2026-07-15T10:05:00Z","configuration":{"type":{"displayName":"Build"},"settings":{"displayName":"CI Build"}},"context":{"buildId":991}}]
'''),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final details = await provider.getCheckDetails(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        check: check,
      );
      expect(details, isNotNull);
      expect(details!.workflow, 'Build');
      expect(details.description, 'CI Build');
      expect(details.event, isNull);
      expect(details.startedAt, DateTime.parse('2026-07-15T10:00:00Z'));
      expect(details.completedAt, DateTime.parse('2026-07-15T10:05:00Z'));
      expect(
        details.url,
        'https://dev.azure.com/myorg/myproject/_build/results?buildId=991',
      );
    });

    test('returns null when no policy matches the check name', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(
          '[{"status":"approved",'
          '"configuration":{"type":{"displayName":"Other"}}}]',
        ),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final details = await provider.getCheckDetails(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        check: check,
      );
      expect(details, isNull);
    });
  });

  group('AzureDevOpsForgeProvider.retargetBodyJson', () {
    test('prefixes bare branch names with refs/heads/', () {
      expect(
        AzureDevOpsForgeProvider.retargetBodyJson('main'),
        '{"targetRefName":"refs/heads/main"}',
      );
    });

    test('keeps already-prefixed refs unchanged', () {
      expect(
        AzureDevOpsForgeProvider.retargetBodyJson('refs/heads/develop'),
        '{"targetRefName":"refs/heads/develop"}',
      );
    });
  });

  group('AzureDevOpsForgeProvider.updateReview', () {
    const readBack = '''
{"pullRequestId":42,"title":"feat: renamed","status":"active","isDraft":false,"sourceRefName":"refs/heads/feature","targetRefName":"refs/heads/develop","mergeStatus":"succeeded","createdBy":{"displayName":"Ley"}}
''';

    test('updates the title then reads the PR back', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('{}'),
        _ok(readBack),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        input: const UpdateReviewInput(title: 'feat: renamed'),
      );

      expect(runner.calls, hasLength(2));
      final updateCall = runner.calls.first;
      expect(updateCall.arguments.sublist(0, 3), <String>[
        'repos',
        'pr',
        'update',
      ]);
      expect(updateCall.optionValue('id'), '42');
      expect(updateCall.optionValue('title'), 'feat: renamed');
      expect(runner.calls[1].arguments.sublist(0, 3), <String>[
        'repos',
        'pr',
        'show',
      ]);
      expect(result, isA<UpdateReviewSuccess>());
      expect((result as UpdateReviewSuccess).review.title, 'feat: renamed');
    });

    test('retargets via az devops invoke PATCH', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('{}'),
        _ok(readBack),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        input: const UpdateReviewInput(baseBranch: 'develop'),
      );

      expect(runner.calls, hasLength(2));
      final invokeCall = runner.calls.first;
      expect(invokeCall.arguments.sublist(0, 2), <String>['devops', 'invoke']);
      expect(invokeCall.optionValue('area'), 'git');
      expect(invokeCall.optionValue('resource'), 'pullrequests');
      expect(invokeCall.optionValue('http-method'), 'PATCH');
      expect(invokeCall.optionValue('api-version'), '7.1');
      expect(invokeCall.arguments, contains('project=myproject'));
      expect(invokeCall.arguments, contains('repositoryId=myrepo'));
      expect(invokeCall.arguments, contains('pullRequestId=42'));
      expect(invokeCall.optionValue('in-file'), isNotNull);
      expect(
        invokeCall.optionValue('organization'),
        'https://dev.azure.com/myorg',
      );
      expect(result, isA<UpdateReviewSuccess>());
      expect((result as UpdateReviewSuccess).review.baseBranch, 'develop');
    });

    test('blocks retargeting when the project is unknown', () async {
      final runner = FakeRecordingProcessRunner(<Object>[]);
      final provider = AzureDevOpsForgeProvider(runner);

      final result = await provider.updateReview(
        identity: const GitRemoteIdentity(
          provider: GitHostingProvider.azureDevops,
          host: 'dev.azure.com',
          owner: 'myorg',
          repo: 'myrepo',
        ),
        repoPath: '/repo',
        number: 42,
        input: const UpdateReviewInput(baseBranch: 'develop'),
      );
      expect(runner.calls, isEmpty);
      expect(result, isA<UpdateReviewFailure>());
      expect(
        (result as UpdateReviewFailure).code,
        UpdateReviewErrorCode.blocked,
      );
    });

    test('runs title update before retarget and then reads back', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('{}'),
        _ok('{}'),
        _ok(readBack),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        input: const UpdateReviewInput(
          title: 'feat: renamed',
          baseBranch: 'develop',
        ),
      );
      expect(runner.calls, hasLength(3));
      expect(runner.calls[0].arguments.sublist(0, 3), <String>[
        'repos',
        'pr',
        'update',
      ]);
      expect(runner.calls[1].arguments.sublist(0, 2), <String>[
        'devops',
        'invoke',
      ]);
      expect(runner.calls[2].arguments.sublist(0, 3), <String>[
        'repos',
        'pr',
        'show',
      ]);
      expect(result, isA<UpdateReviewSuccess>());
    });

    test('notes a possible partial update when retargeting fails', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('{}'),
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'TF401027: You need the Git PullRequestContribute permission',
        ),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        input: const UpdateReviewInput(
          title: 'feat: renamed',
          baseBranch: 'develop',
        ),
      );
      expect(result, isA<UpdateReviewFailure>());
      final failure = result as UpdateReviewFailure;
      expect(failure.code, UpdateReviewErrorCode.unknown);
      expect(
        failure.message,
        contains('the title may already have been updated'),
      );
    });
  });

  group('AzureDevOpsForgeProvider review actions', () {
    for (final entry in <(ReviewMergeMethod, String)>[
      (ReviewMergeMethod.mergeCommit, 'false'),
      (ReviewMergeMethod.squash, 'true'),
    ]) {
      test('completes with squash=${entry.$2}', () async {
        final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
        final provider = AzureDevOpsForgeProvider(runner);

        await provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          method: entry.$1,
        );

        final call = runner.calls.single;
        expect(call.arguments.sublist(0, 3), <String>['repos', 'pr', 'update']);
        expect(call.optionValue('status'), 'completed');
        expect(call.optionValue('squash'), entry.$2);
        expect(call.optionValue('organization'), 'https://dev.azure.com/myorg');
      });
    }

    test('does not expose rebase through the Azure CLI', () async {
      final runner = FakeRecordingProcessRunner(<Object>[]);
      final provider = AzureDevOpsForgeProvider(runner);

      expect(
        () => provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          method: ReviewMergeMethod.rebase,
        ),
        throwsA(isA<Exception>()),
      );
      expect(runner.calls, isEmpty);
    });

    test('abandons the pull request when closing', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
      final provider = AzureDevOpsForgeProvider(runner);

      await provider.closeReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
      );

      final call = runner.calls.single;
      expect(call.optionValue('status'), 'abandoned');
      expect(call.optionValue('organization'), 'https://dev.azure.com/myorg');
    });

    for (final draft in <bool>[false, true]) {
      test('sets draft=$draft through the Azure CLI', () async {
        final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
        final provider = AzureDevOpsForgeProvider(runner);

        await provider.setReviewDraft(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          draft: draft,
        );

        final call = runner.calls.single;
        expect(call.arguments.sublist(0, 3), <String>['repos', 'pr', 'update']);
        expect(call.optionValue('draft'), '$draft');
        expect(call.optionValue('organization'), 'https://dev.azure.com/myorg');
      });
    }
  });

  group('AzureDevOpsForgeProvider.createReview', () {
    test('creates and maps the returned PR, passing --draft', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"pullRequestId":7,"title":"feat: y","status":"active","isDraft":true,"sourceRefName":"refs/heads/feat","targetRefName":"refs/heads/main","mergeStatus":"queued","createdBy":{"displayName":"Ley"}}
'''),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final result = await provider.createReview(
        identity: _identity,
        repoPath: '/repo',
        input: const CreateReviewInput(
          provider: GitHostingProvider.azureDevops,
          title: 'feat: y',
          baseBranch: 'main',
          headBranch: 'feat',
          draft: true,
        ),
      );
      expect(result, isA<CreateReviewSuccess>());
      final review = (result as CreateReviewSuccess).review;
      expect(review.number, 7);
      expect(review.state, HostedReviewState.draft);
      final call = runner.calls.single;
      expect(call.arguments.sublist(0, 3), <String>['repos', 'pr', 'create']);
      expect(call.optionValue('source-branch'), 'feat');
      expect(call.optionValue('target-branch'), 'main');
      expect(call.optionValue('draft'), 'true');
    });
  });
}
