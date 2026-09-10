import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
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

    test('rewrites a merge-commit ruleset rejection', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr:
              'GraphQL: Merge commits are not allowed on this repository. '
              '(mergePullRequest)',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      expect(
        () => provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 123,
          method: .mergeCommit,
        ),
        throwsA(
          isA<ForgeRequestFailed>().having(
            (error) => error.message,
            'message',
            contains('Use squash and merge or rebase and merge instead.'),
          ),
        ),
      );
    });

    test('filters merge methods from repository settings', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":false,"squashMergeAllowed":true,"rebaseMergeAllowed":false}
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final methods = await provider.allowedMergeMethods(
        identity: _identity,
        repoPath: '/repo',
      );

      expect(methods, <ReviewMergeMethod>[ReviewMergeMethod.squash]);
      final call = runner.calls.single;
      expect(call.arguments.sublist(0, 2), <String>['repo', 'view']);
      expect(call.optionValue('json'), contains('mergeCommitAllowed'));
    });

    test('intersects repository settings with branch rulesets', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
        _ok('''
[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]}}]
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final methods = await provider.allowedMergeMethods(
        identity: _identity,
        repoPath: '/repo',
        baseBranch: 'main',
      );

      expect(methods, <ReviewMergeMethod>[ReviewMergeMethod.squash]);
      expect(runner.calls, hasLength(2));
      expect(runner.calls[1].arguments.take(2), <String>['api', '--hostname']);
      expect(
        runner.calls[1].arguments.last,
        'repos/leynier/alera/rules/branches/main',
      );
    });

    test('drops merge commits when linear history is required', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
        _ok('[{"type":"required_linear_history"}]'),
      ]);
      final provider = GitHubForgeProvider(runner);

      final methods = await provider.allowedMergeMethods(
        identity: _identity,
        repoPath: '/repo',
        baseBranch: 'main',
      );

      expect(methods, <ReviewMergeMethod>[
        ReviewMergeMethod.squash,
        ReviewMergeMethod.rebase,
      ]);
    });

    test(
      'keeps repository methods when a pull_request rule has no merge methods',
      () async {
        final runner = FakeRecordingProcessRunner(<Object>[
          _ok('''
{"mergeCommitAllowed":false,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
          _ok('''
[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]
'''),
        ]);
        final provider = GitHubForgeProvider(runner);

        final methods = await provider.allowedMergeMethods(
          identity: _identity,
          repoPath: '/repo',
          baseBranch: 'main',
        );

        expect(methods, <ReviewMergeMethod>[
          ReviewMergeMethod.squash,
          ReviewMergeMethod.rebase,
        ]);
      },
    );

    test('keeps repository methods when the branch has no rules', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":false,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
        _ok('[]'),
      ]);
      final provider = GitHubForgeProvider(runner);

      final methods = await provider.allowedMergeMethods(
        identity: _identity,
        repoPath: '/repo',
        baseBranch: 'main',
      );

      expect(methods, <ReviewMergeMethod>[
        ReviewMergeMethod.squash,
        ReviewMergeMethod.rebase,
      ]);
    });

    test('fails closed when branch rulesets are not found', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
        const ProcessRunOutput(exitCode: 1, stdout: '', stderr: 'Not Found'),
      ]);
      final provider = GitHubForgeProvider(runner);

      expect(
        () => provider.allowedMergeMethods(
          identity: _identity,
          repoPath: '/repo',
          baseBranch: 'main',
        ),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });

    test('fails closed when repository merge flags are missing', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('{}')]);
      final provider = GitHubForgeProvider(runner);

      expect(
        () => provider.allowedMergeMethods(
          identity: _identity,
          repoPath: '/repo',
        ),
        throwsA(
          isA<ForgeRequestFailed>().having(
            (error) => error.message,
            'message',
            'GitHub did not return the repository merge methods.',
          ),
        ),
      );
    });

    test('fails closed when branch rulesets are malformed', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
        _ok('''
{"type":"pull_request","parameters":{"allowed_merge_methods":"squash"}}
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      expect(
        () => provider.allowedMergeMethods(
          identity: _identity,
          repoPath: '/repo',
          baseBranch: 'main',
        ),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });

    test('fails closed when branch rulesets cannot be read', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":true}
'''),
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'API rate limit exceeded',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      expect(
        () => provider.allowedMergeMethods(
          identity: _identity,
          repoPath: '/repo',
          baseBranch: 'main',
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
}
