import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_thread_backlog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_request_agent_watch_fixtures.dart';

void main() {
  group('prompts', () {
    test('restack prompt names the merge base and forbids a push', () {
      expect(pullRequestRestackPrompt, contains('since the merge base'));
      expect(pullRequestRestackPrompt, contains('Do not push.'));
      expect(pullRequestRestackPrompt, isNot(contains('`')));
    });

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

  test('watch scope reports emptiness and round-trips through json', () {
    const none = PullRequestAgentWatchScope(
      checks: false,
      comments: false,
      conflicts: false,
    );
    expect(none.isEmpty, isTrue);
    expect(PullRequestAgentWatchScope.defaults.isEmpty, isFalse);
    expect(
      PullRequestAgentWatchScope.fromJson(<String, Object?>{'comments': false}),
      const PullRequestAgentWatchScope(comments: false),
    );
    expect(PullRequestAgentWatchScope.fromJson(none.toMap()), none);
  });

  test('labels both watch modes', () {
    expect(pullRequestAgentWatchModeLabel(.fix), 'Watching: Fix');
    expect(
      pullRequestAgentWatchModeLabel(.fixAndMerge),
      'Watching: Fix and Merge',
    );
  });

  test('tooltip lists mode and each scope toggle', () {
    expect(
      pullRequestAgentWatchTooltip(
        mode: .fixAndMerge,
        scope: const PullRequestAgentWatchScope(conflicts: false),
      ),
      'Watching: Fix and Merge\n'
      'Failed Checks: On\n'
      'Review Comments: On\n'
      'Merge Conflicts: Off',
    );
  });

  test('watch records round-trip through json', () {
    const session = PullRequestAgentWatchSession(
      workspaceId: 'w',
      reviewNumber: 801,
      mode: .fix,
      binding: AgentTaskDispatchBinding(tabId: 'tab-1', label: 'Grok'),
      scope: pullRequestWatchTestScope,
      watchScope: PullRequestAgentWatchScope(comments: false),
      lastDispatch: PullRequestAgentWatchDispatchMark(
        headSha: 'abc',
        checksFailed: true,
        threadIds: <String>{'T1'},
      ),
    );
    final record = PullRequestAgentWatchRecord.fromSession(session);
    final restored = PullRequestAgentWatchRecord.fromJson(record.toJson());
    expect(restored.workspaceId, 'w');
    expect(restored.reviewNumber, 801);
    expect(restored.watchScope.comments, isFalse);
    expect(restored.lastDispatch?.headSha, 'abc');
    expect(restored.lastDispatch?.threadIds, <String>{'T1'});
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
