import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_prompts.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
