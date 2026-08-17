import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _identity = GitRemoteIdentity(
  provider: GitHostingProvider.github,
  host: 'github.com',
  owner: 'leynier',
  repo: 'alera',
);

const _stackSearch = '[{"number":429}]';
const _stackDetail = '''
{
  "number": 429,
  "base": {"ref": "main"},
  "open": true,
  "created_at": "2026-08-16T07:30:12Z",
  "pull_requests": [
    {
      "number": 423,
      "title": "fix: first layer",
      "state": "closed",
      "draft": false,
      "merged_at": "2026-08-16T08:01:48Z",
      "created_at": "2026-08-16T07:10:00Z",
      "html_url": "https://github.com/leynier/alera/pull/423",
      "user": {"login": "leynier"},
      "head": {"ref": "feature/one", "sha": "aaa"},
      "base": {"ref": "main"}
    },
    {
      "number": 424,
      "title": "feat: second layer",
      "state": "open",
      "draft": true,
      "merged_at": null,
      "created_at": "2026-08-16T07:20:00Z",
      "html_url": "https://github.com/leynier/alera/pull/424",
      "user": {"login": "leynier"},
      "head": {"ref": "feature/two", "sha": "bbb"},
      "base": {"ref": "feature/one"}
    }
  ]
}
''';

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  group('GitHubForgeProvider stacks', () {
    test('loads the stack containing a pull request', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(_stackSearch),
        _ok(_stackDetail),
      ]);
      final provider = GitHubForgeProvider(runner);

      final stack = await provider.getStackForReview(
        identity: _identity,
        repoPath: '/repo',
        reviewNumber: 423,
      );

      expect(stack, isNotNull);
      expect(stack!.number, 429);
      expect(stack.baseBranch, 'main');
      expect(stack.open, isTrue);
      expect(stack.entries, hasLength(2));
      expect(stack.entries[0].position, 1);
      expect(stack.entries[0].review.state, HostedReviewState.merged);
      expect(stack.entries[1].position, 2);
      expect(stack.entries[1].review.state, HostedReviewState.draft);
      expect(stack.entries[1].review.baseBranch, 'feature/one');
      expect(stack.positionForReview(424), 2);

      expect(runner.calls[0].arguments, <String>[
        'api',
        '--hostname',
        'github.com',
        'repos/leynier/alera/stacks?pull_request=423',
      ]);
      expect(runner.calls[1].arguments, <String>[
        'api',
        '--hostname',
        'github.com',
        'repos/leynier/alera/stacks/429',
      ]);
    });

    test('returns null when the pull request has no stack', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('[]')]);
      final provider = GitHubForgeProvider(runner);

      final stack = await provider.getStackForReview(
        identity: _identity,
        repoPath: '/repo',
        reviewNumber: 99,
      );

      expect(stack, isNull);
      expect(runner.calls, hasLength(1));
    });

    test('links existing pull requests bottom to top', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('Stack created'),
        _ok(_stackSearch),
        _ok(_stackDetail),
      ]);
      final provider = GitHubForgeProvider(runner);

      final stack = await provider.linkReviewStack(
        identity: _identity,
        repoPath: '/repo',
        reviewNumbers: const <int>[423, 424],
        baseBranch: 'main',
      );

      expect(stack.number, 429);
      expect(runner.calls.first.arguments, <String>[
        'stack',
        'link',
        '423',
        '424',
        '--base',
        'main',
      ]);
      expect(runner.calls.first.workingDirectory, '/repo');
    });

    test('appends pull requests to an existing stack', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('Stack updated'),
        _ok(_stackSearch),
        _ok(_stackDetail),
      ]);
      final provider = GitHubForgeProvider(runner);

      await provider.linkReviewStack(
        identity: _identity,
        repoPath: '/repo',
        stackNumber: 429,
        reviewNumbers: const <int>[424],
      );

      expect(runner.calls.first.arguments, <String>[
        'stack',
        'link',
        '429',
        '424',
      ]);
    });

    test('reports a missing gh-stack extension', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'unknown command "stack" for "gh"',
        ),
      ]);
      final provider = GitHubForgeProvider(runner);

      expect(
        () => provider.linkReviewStack(
          identity: _identity,
          repoPath: '/repo',
          reviewNumbers: const <int>[423, 424],
        ),
        throwsA(
          isA<ForgeCliMissing>().having(
            (error) => error.message,
            'message',
            contains('github/gh-stack'),
          ),
        ),
      );
    });

    for (final entry in <(ReviewMergeMethod, String)>[
      (ReviewMergeMethod.mergeCommit, 'merge'),
      (ReviewMergeMethod.squash, 'squash'),
      (ReviewMergeMethod.rebase, 'rebase'),
    ]) {
      test('merges the stack with ${entry.$2}', () async {
        final runner = FakeRecordingProcessRunner(<Object>[_ok('merged')]);
        final provider = GitHubForgeProvider(runner);

        await provider.mergeReviewStack(
          identity: _identity,
          repoPath: '/repo',
          reviewNumber: 424,
          method: entry.$1,
        );

        expect(runner.calls.single.arguments, <String>[
          'stack',
          'merge',
          '424',
          '--yes',
          '--merge-method',
          entry.$2,
        ]);
      });
    }

    test('rejects provider-default stack merges', () async {
      final provider = GitHubForgeProvider(
        FakeRecordingProcessRunner(<Object>[]),
      );

      expect(
        () => provider.mergeReviewStack(
          identity: _identity,
          repoPath: '/repo',
          reviewNumber: 424,
          method: ReviewMergeMethod.providerDefault,
        ),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });
  });
}
