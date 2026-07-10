import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _identity = GitRemoteIdentity(
  provider: GitHostingProvider.github,
  host: 'github.com',
  owner: 'leynier',
  repo: 'alera',
);

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  group('GitHubForgeProvider.getReviewForBranch', () {
    test('builds gh pr list argv and maps the first PR', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"number":123,"title":"feat: x","state":"OPEN","url":"https://github.com/leynier/alera/pull/123","isDraft":false,"mergeable":"MERGEABLE","headRefName":"feature","baseRefName":"main","headRefOid":"abc","author":{"login":"leynier"}}]
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final review = await provider.getReviewForBranch(
        identity: _identity,
        repoPath: '/repo',
        branch: 'feature',
      );

      final call = runner.calls.single;
      expect(call.executable, 'gh');
      expect(call.workingDirectory, '/repo');
      expect(call.arguments.sublist(0, 2), <String>['pr', 'list']);
      expect(call.optionValue('repo'), 'leynier/alera');
      expect(call.optionValue('head'), 'feature');
      expect(call.optionValue('state'), 'open');
      expect(review, isNotNull);
      expect(review!.number, 123);
      expect(review.state, HostedReviewState.open);
      expect(review.mergeable, HostedReviewMergeable.mergeable);
      expect(review.author, 'leynier');
      expect(review.headBranch, 'feature');
    });

    test('returns null when no PR matches the branch', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('[]')]);
      final provider = GitHubForgeProvider(runner);

      final review = await provider.getReviewForBranch(
        identity: _identity,
        repoPath: '/repo',
        branch: 'feature',
      );
      expect(review, isNull);
    });

    test('prefixes the host for GitHub Enterprise remotes', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('[]')]);
      final provider = GitHubForgeProvider(runner);

      await provider.getReviewForBranch(
        identity: const GitRemoteIdentity(
          provider: GitHostingProvider.github,
          host: 'github.mycorp.com',
          owner: 'team',
          repo: 'svc',
        ),
        repoPath: '/repo',
        branch: 'x',
      );
      expect(runner.calls.single.optionValue('repo'), 'github.mycorp.com/team/svc');
    });
  });

  group('GitHubForgeProvider.getChecks', () {
    test('maps buckets to conclusions and status', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"name":"build","state":"SUCCESS","bucket":"pass","link":"https://ci/build"},
 {"name":"test","state":"FAILURE","bucket":"fail","link":""},
 {"name":"lint","state":"IN_PROGRESS","bucket":"pending","link":""}]
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final checks = await provider.getChecks(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
      );
      expect(checks, hasLength(3));
      expect(checks[0].conclusion, ReviewCheckConclusion.success);
      expect(checks[0].status, ReviewCheckStatus.completed);
      expect(checks[0].url, 'https://ci/build');
      expect(checks[1].conclusion, ReviewCheckConclusion.failure);
      expect(checks[2].conclusion, ReviewCheckConclusion.pending);
      expect(checks[2].status, ReviewCheckStatus.inProgress);
    });

    test('treats a no-checks result as empty, not an error', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'no checks reported on the feature branch',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      final checks = await provider.getChecks(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
      );
      expect(checks, isEmpty);
    });
  });

  group('GitHubForgeProvider.checkAuth', () {
    test('authenticated on exit 0', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
      final provider = GitHubForgeProvider(runner);
      expect(
        await provider.checkAuth(identity: _identity),
        ForgeAuthStatus.authenticated,
      );
      expect(runner.calls.single.optionValue('hostname'), 'github.com');
    });

    test('notAuthenticated on non-zero exit', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'You are not logged into any GitHub hosts.',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);
      expect(
        await provider.checkAuth(identity: _identity),
        ForgeAuthStatus.notAuthenticated,
      );
    });

    test('cliMissing when gh cannot be launched', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        StateError('gh missing'),
      ]);
      final provider = GitHubForgeProvider(runner);
      expect(
        await provider.checkAuth(identity: _identity),
        ForgeAuthStatus.cliMissing,
      );
    });
  });

  group('GitHubForgeProvider.createReview', () {
    test('creates then reads back the PR', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('https://github.com/leynier/alera/pull/456\n'),
        _ok('''
{"number":456,"title":"feat: y","state":"OPEN","url":"https://github.com/leynier/alera/pull/456","isDraft":false,"mergeable":"UNKNOWN","headRefName":"feat","baseRefName":"main","headRefOid":"def","author":{"login":"leynier"}}
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final result = await provider.createReview(
        identity: _identity,
        repoPath: '/repo',
        input: const CreateReviewInput(
          provider: GitHostingProvider.github,
          title: 'feat: y',
          baseBranch: 'main',
          headBranch: 'feat',
        ),
      );
      expect(result, isA<CreateReviewSuccess>());
      expect((result as CreateReviewSuccess).review.number, 456);
      final createCall = runner.calls.first;
      expect(createCall.arguments.sublist(0, 2), <String>['pr', 'create']);
      expect(createCall.optionValue('base'), 'main');
      expect(createCall.optionValue('head'), 'feat');
    });

    test('maps an existing-PR failure to alreadyExists', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'a pull request for branch "feat" already exists',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      final result = await provider.createReview(
        identity: _identity,
        repoPath: '/repo',
        input: const CreateReviewInput(
          provider: GitHostingProvider.github,
          title: 't',
          baseBranch: 'main',
          headBranch: 'feat',
        ),
      );
      expect(result, isA<CreateReviewFailure>());
      expect(
        (result as CreateReviewFailure).code,
        CreateReviewErrorCode.alreadyExists,
      );
    });
  });
}
