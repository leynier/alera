import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_thread_backlog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_request_agent_watch_fixtures.dart';

void main() {
  group('prompts', () {
    test('failed checks prompt names the pull request and omits logs', () {
      final prompt = pullRequestFailedChecksPrompt(42);
      expect(prompt, contains('Pull request #42 checks failed'));
      expect(prompt, contains('Please fix them.'));
      expect(prompt.toLowerCase(), isNot(contains('log')));
      expect(prompt.toLowerCase(), isNot(contains('payload')));
      expect(prompt, isNot(contains('ci.yml')));
    });

    test('watch prompt matches the failed checks prompt for checks only', () {
      expect(
        pullRequestAgentWatchPrompt(
          reviewNumber: 42,
          concerns: const PullRequestAgentWatchConcerns(checksFailed: true),
          baseBranch: 'main',
        ),
        pullRequestFailedChecksPrompt(42),
      );
    });

    test('watch prompt names every concern without comment bodies', () {
      final prompt = pullRequestAgentWatchPrompt(
        reviewNumber: 42,
        concerns: const PullRequestAgentWatchConcerns(
          checksFailed: true,
          conflict: true,
          threads: <PendingReviewThread>[
            PendingReviewThread(id: 'T1', path: 'lib/a.dart'),
            PendingReviewThread(id: 'T2'),
          ],
        ),
        baseBranch: 'main',
      );
      expect(
        prompt,
        'Pull request #42 has merge conflicts with main, failing checks, and '
        '2 unresolved review threads. Please resolve the conflicts, fix the '
        'checks, and address the review comments. Resolve each review thread '
        'once its fix is pushed.',
      );
      expect(prompt, isNot(contains('`')));
    });

    test('watch prompt stays readable when nothing is pending', () {
      expect(
        pullRequestAgentWatchPrompt(
          reviewNumber: 42,
          concerns: const PullRequestAgentWatchConcerns(),
        ),
        'Please check pull request #42 and fix anything that blocks it.',
      );
    });

    test('watch prompt handles a single thread and an unknown base', () {
      expect(
        pullRequestAgentWatchPrompt(
          reviewNumber: 7,
          concerns: const PullRequestAgentWatchConcerns(
            conflict: true,
            threads: <PendingReviewThread>[PendingReviewThread(id: 'T1')],
          ),
        ),
        'Pull request #7 has merge conflicts with its base branch and '
        '1 unresolved review thread. Please resolve the conflicts and address '
        'the review comments. Resolve each review thread once its fix is '
        'pushed.',
      );
    });
  });

  test('labels both watch modes', () {
    expect(pullRequestAgentWatchModeLabel(.fix), 'Watching: Fix');
    expect(
      pullRequestAgentWatchModeLabel(.fixAndMerge),
      'Watching: Fix and Merge',
    );
  });

  group('pullRequestAgentWatchConcerns', () {
    test('collects every concern inside the scope', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: pullRequestWatchSnapshot(
          rollup: .failure,
          mergeable: .conflicting,
          comments: <ReviewComment>[pullRequestWatchThread('T1')],
        ),
        scope: PullRequestAgentWatchScope.defaults,
      );
      expect(concerns.checksFailed, isTrue);
      expect(concerns.conflict, isTrue);
      expect(concerns.threadIds, <String>{'T1'});
      expect(pullRequestAgentWatchInjectsOnStart(concerns), isTrue);
    });

    test('ignores concerns outside the scope', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: pullRequestWatchSnapshot(
          rollup: .failure,
          mergeable: .conflicting,
          comments: <ReviewComment>[pullRequestWatchThread('T1')],
        ),
        scope: const PullRequestAgentWatchScope(
          checks: false,
          comments: false,
          conflicts: false,
        ),
      );
      expect(concerns.isEmpty, isTrue);
      expect(pullRequestAgentWatchInjectsOnStart(concerns), isFalse);
    });

    test('does not treat unknown mergeability as a conflict', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: pullRequestWatchSnapshot(mergeable: .unknown),
        scope: PullRequestAgentWatchScope.defaults,
      );
      expect(concerns.conflict, isFalse);
    });

    test('skips threads written only by the pull request author', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: pullRequestWatchSnapshot(
          comments: <ReviewComment>[
            pullRequestWatchThread('T1', author: 'leynier'),
          ],
        ),
        scope: PullRequestAgentWatchScope.defaults,
      );
      expect(concerns.isEmpty, isTrue);
    });
  });

  test(
    'accumulates the dispatch mark on one head and resets on a new head',
    () {
      const first = PullRequestAgentWatchDispatchMark(
        headSha: 'abc123',
        checksFailed: true,
        threadIds: <String>{'T1'},
      );
      final same = pullRequestAgentWatchDispatchMark(
        previous: first,
        headSha: 'abc123',
        concerns: const PullRequestAgentWatchConcerns(
          threads: <PendingReviewThread>[PendingReviewThread(id: 'T2')],
        ),
      );
      expect(same.checksFailed, isTrue);
      expect(same.threadIds, <String>{'T1', 'T2'});

      final next = pullRequestAgentWatchDispatchMark(
        previous: first,
        headSha: 'def456',
        concerns: const PullRequestAgentWatchConcerns(conflict: true),
      );
      expect(next.checksFailed, isFalse);
      expect(next.conflict, isTrue);
      expect(next.threadIds, isEmpty);
    },
  );
}
