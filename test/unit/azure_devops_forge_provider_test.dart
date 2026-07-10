import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
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
    test('builds az repos pr list argv and maps the first PR', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"pullRequestId":42,"title":"feat: x","status":"active","isDraft":false,"sourceRefName":"refs/heads/feature","targetRefName":"refs/heads/main","mergeStatus":"succeeded","createdBy":{"displayName":"Ley"},"lastMergeSourceCommit":{"commitId":"abc"}}]
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
      expect(review, isNotNull);
      expect(review!.number, 42);
      expect(review.state, HostedReviewState.open);
      expect(review.mergeable, HostedReviewMergeable.mergeable);
      expect(review.headBranch, 'feature');
      expect(review.baseBranch, 'main');
      expect(
        review.url,
        'https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/42',
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
