import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _identity = GitRemoteIdentity(
  provider: .github,
  host: 'github.com',
  owner: 'leynier',
  repo: 'alera',
);

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  group('GitHubForgeProvider.getReviewForBranch', () {
    test('builds gh pr list argv and maps the newest PR', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"number":123,"title":"feat: older","state":"OPEN","url":"https://github.com/leynier/alera/pull/123","createdAt":"2026-07-10T00:00:00Z","isDraft":false,"mergeable":"MERGEABLE","headRefName":"feature","baseRefName":"main","headRefOid":"abc","author":{"login":"leynier"}},
 {"number":124,"title":"feat: newest","state":"OPEN","url":"https://github.com/leynier/alera/pull/124","createdAt":"2026-07-11T00:00:00Z","isDraft":false,"mergeable":"MERGEABLE","headRefName":"feature","baseRefName":"main","headRefOid":"def","author":{"login":"leynier"}}]
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
      expect(call.optionValue('limit'), '100');
      expect(review, isNotNull);
      expect(review!.number, 124);
      expect(review.title, 'feat: newest');
      expect(review.createdAt, DateTime.parse('2026-07-11T00:00:00Z'));
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

    test('rejects a GitHub Enterprise custom HTTPS port', () async {
      final provider = GitHubForgeProvider(FakeRecordingProcessRunner([]));

      expect(
        () => provider.getReviewForBranch(
          identity: const GitRemoteIdentity(
            provider: .github,
            host: 'github.mycorp.com:8443',
            owner: 'team',
            repo: 'svc',
          ),
          repoPath: '/repo',
          branch: 'x',
        ),
        throwsA(
          isA<ForgeRequestFailed>().having(
            (error) => error.message,
            'message',
            contains('custom HTTPS ports'),
          ),
        ),
      );
    });
  });

  group('GitHubForgeProvider.getReviewBatch', () {
    test('loads branches and linked PRs in one GraphQL process', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"data":{"repository":{
  "branch0":{"nodes":[{"number":123,"title":"feat: sidebar status","state":"OPEN","url":"https://github.com/leynier/alera/pull/123","createdAt":"2026-09-01T00:00:00Z","isDraft":false,"mergeable":"MERGEABLE","headRefName":"feature","baseRefName":"main","headRefOid":"abc","commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null,"detailsUrl":"https://ci/build"},{"__typename":"StatusContext","context":"lint","state":"FAILURE","targetUrl":"https://ci/lint"}]}}}}]}}]},
  "review0":{"number":77,"title":"merged work","state":"MERGED","url":"https://github.com/leynier/alera/pull/77","createdAt":"2026-08-01T00:00:00Z","isDraft":false,"mergeable":"UNKNOWN","headRefName":"old-feature","baseRefName":"main","headRefOid":"def","commits":{"nodes":[]}}
}}}
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final batch = await provider.getReviewBatch(
        identity: _identity,
        repoPath: '/repo',
        branches: const <String>{'feature'},
        reviewNumbers: const <int>{77},
      );

      final call = runner.calls.single;
      expect(call.executable, 'gh');
      expect(call.arguments.take(2), <String>['api', 'graphql']);
      expect(call.workingDirectory, '/repo');
      expect(call.arguments, contains('branch0=feature'));
      expect(call.arguments, contains('number0=77'));
      expect(
        call.arguments.firstWhere((argument) => argument.startsWith('query=')),
        contains('statusCheckRollup'),
      );

      final feature = batch.byBranch['feature'];
      expect(feature, isNotNull);
      expect(feature!.review.number, 123);
      expect(feature.checks, hasLength(2));
      expect(feature.checks[0].status, ReviewCheckStatus.inProgress);
      expect(feature.checks[0].conclusion, ReviewCheckConclusion.pending);
      expect(feature.checks[1].conclusion, ReviewCheckConclusion.failure);
      expect(batch.byNumber[123], same(feature));
      expect(batch.byNumber[77]!.review.state, HostedReviewState.merged);
      expect(batch.byBranch['old-feature']!.review.number, 77);
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

  group('GitHubForgeProvider.getCheckDetails', () {
    const check = ReviewCheck(
      name: 'build',
      status: .completed,
      conclusion: .success,
      url: 'https://ci/build/2',
    );

    test('requests detail fields and maps the matching entry', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        // Non-zero exit with valid stdout mirrors pending/failing checks.
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '''
[{"name":"build","state":"SUCCESS","bucket":"pass","link":"https://ci/build/2","description":"Build finished","event":"push","workflow":"CI","startedAt":"2026-07-15T10:00:00Z","completedAt":"2026-07-15T10:05:00Z"}]
''',
          stderr: '',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      final details = await provider.getCheckDetails(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        check: check,
      );

      final call = runner.calls.single;
      expect(call.arguments.sublist(0, 2), <String>['pr', 'checks']);
      expect(
        call.optionValue('json'),
        'name,state,bucket,link,description,event,workflow,'
        'startedAt,completedAt',
      );
      expect(details, isNotNull);
      expect(details!.description, 'Build finished');
      expect(details.workflow, 'CI');
      expect(details.event, 'push');
      expect(details.startedAt, DateTime.parse('2026-07-15T10:00:00Z'));
      expect(details.completedAt, DateTime.parse('2026-07-15T10:05:00Z'));
      expect(details.url, 'https://ci/build/2');
    });

    test('disambiguates duplicate names by link', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[{"name":"build","state":"SUCCESS","bucket":"pass","link":"https://ci/build/1","workflow":"CI 1"},
 {"name":"build","state":"SUCCESS","bucket":"pass","link":"https://ci/build/2","workflow":"CI 2"}]
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final details = await provider.getCheckDetails(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        check: check,
      );
      expect(details!.workflow, 'CI 2');
    });

    test('returns null when no entry matches the check name', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('[{"name":"other","state":"SUCCESS","bucket":"pass","link":""}]'),
      ]);
      final provider = GitHubForgeProvider(runner);

      final details = await provider.getCheckDetails(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        check: check,
      );
      expect(details, isNull);
    });
  });

  group('GitHubForgeProvider.updateReview', () {
    const readBack = '''
{"number":123,"title":"feat: renamed","state":"OPEN","url":"https://github.com/leynier/alera/pull/123","isDraft":false,"mergeable":"MERGEABLE","headRefName":"feature","baseRefName":"develop","headRefOid":"abc","author":{"login":"leynier"}}
''';

    test('edits title and base then reads the PR back', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(''),
        _ok(readBack),
      ]);
      final provider = GitHubForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        input: const UpdateReviewInput(
          title: 'feat: renamed',
          baseBranch: 'develop',
        ),
      );

      final editCall = runner.calls.first;
      expect(editCall.arguments.sublist(0, 3), <String>['pr', 'edit', '123']);
      expect(editCall.optionValue('title'), 'feat: renamed');
      expect(editCall.optionValue('base'), 'develop');
      expect(result, isA<UpdateReviewSuccess>());
      expect((result as UpdateReviewSuccess).review.title, 'feat: renamed');
      expect(result.review.baseBranch, 'develop');
    });

    test('omits --base when only the title changes', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(''),
        _ok(readBack),
      ]);
      final provider = GitHubForgeProvider(runner);

      await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        input: const UpdateReviewInput(title: 'feat: renamed'),
      );
      final editCall = runner.calls.first;
      expect(editCall.optionValue('title'), 'feat: renamed');
      expect(editCall.arguments, isNot(contains('--base')));
    });

    test('maps an authentication failure', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'error: not logged in, run gh auth login',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        input: const UpdateReviewInput(title: 't'),
      );
      expect(result, isA<UpdateReviewFailure>());
      expect(
        (result as UpdateReviewFailure).code,
        UpdateReviewErrorCode.notAuthenticated,
      );
    });

    test('maps a launch failure to cliMissing', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        StateError('gh missing'),
      ]);
      final provider = GitHubForgeProvider(runner);

      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
        input: const UpdateReviewInput(title: 't'),
      );
      expect(result, isA<UpdateReviewFailure>());
      expect(
        (result as UpdateReviewFailure).code,
        UpdateReviewErrorCode.cliMissing,
      );
    });
  });

  group('GitHubForgeProvider review actions', () {
    for (final entry in <(ReviewMergeMethod, String)>[
      (ReviewMergeMethod.mergeCommit, '--merge'),
      (ReviewMergeMethod.squash, '--squash'),
      (ReviewMergeMethod.rebase, '--rebase'),
    ]) {
      test('merges with ${entry.$2}', () async {
        final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
        final provider = GitHubForgeProvider(runner);

        await provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 123,
          method: entry.$1,
        );

        final call = runner.calls.single;
        expect(call.arguments.sublist(0, 3), <String>['pr', 'merge', '123']);
        expect(call.optionValue('repo'), 'leynier/alera');
        expect(call.arguments, contains(entry.$2));
      });
    }

    test('rejects the provider-default merge method', () async {
      final provider = GitHubForgeProvider(FakeRecordingProcessRunner([]));

      expect(
        () => provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 123,
          method: .providerDefault,
        ),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });

    test('closes the pull request through gh', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
      final provider = GitHubForgeProvider(runner);

      await provider.closeReview(
        identity: _identity,
        repoPath: '/repo',
        number: 123,
      );

      final call = runner.calls.single;
      expect(call.arguments.sublist(0, 3), <String>['pr', 'close', '123']);
      expect(call.optionValue('repo'), 'leynier/alera');
    });

    for (final entry in <(bool, bool)>[(false, false), (true, true)]) {
      test(
        entry.$1
            ? 'converts the pull request to draft through gh'
            : 'marks the pull request ready through gh',
        () async {
          final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
          final provider = GitHubForgeProvider(runner);

          await provider.setReviewDraft(
            identity: _identity,
            repoPath: '/repo',
            number: 123,
            draft: entry.$1,
          );

          final call = runner.calls.single;
          expect(call.arguments.sublist(0, 3), <String>['pr', 'ready', '123']);
          expect(call.optionValue('repo'), 'leynier/alera');
          expect(call.arguments.contains('--undo'), entry.$2);
        },
      );
    }
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

    test('checks authentication for the GitHub Enterprise host', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
      final provider = GitHubForgeProvider(runner);
      await provider.checkAuth(
        identity: const GitRemoteIdentity(
          provider: .github,
          host: 'github.mycorp.com',
          owner: 'team',
          repo: 'svc',
        ),
      );
      expect(runner.calls.single.optionValue('hostname'), 'github.mycorp.com');
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
          provider: .github,
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
          provider: .github,
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
