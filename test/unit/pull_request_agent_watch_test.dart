import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_prompts.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scope = WorkspacePullRequestScope(
    workspaceId: 'workspace-1',
    repoPath: '/repo',
  );
  const session = PullRequestAgentWatchSession(
    workspaceId: 'workspace-1',
    reviewNumber: 42,
    mode: .fix,
    binding: AgentTaskDispatchBinding(tabId: 'tab-1'),
    scope: scope,
  );

  group('pullRequestFailedChecksPrompt', () {
    test('names the pull request and omits check logs', () {
      final prompt = pullRequestFailedChecksPrompt(42);
      expect(prompt, contains('Pull request #42 checks failed'));
      expect(prompt, contains('Please fix them.'));
      expect(prompt.toLowerCase(), isNot(contains('log')));
      expect(prompt.toLowerCase(), isNot(contains('payload')));
      expect(prompt, isNot(contains('ci.yml')));
      expect(pullRequestAgentWatchPrompt(42), prompt);
    });
  });

  group('pullRequestAgentWatchModeLabel', () {
    test('labels both watch modes', () {
      expect(pullRequestAgentWatchModeLabel(.fix), 'Watching: Fix');
      expect(
        pullRequestAgentWatchModeLabel(.fixAndMerge),
        'Watching: Fix and Merge',
      );
    });
  });

  group('pullRequestAgentWatchInjectsOnStart', () {
    test('injects only when checks have already failed', () {
      expect(pullRequestAgentWatchInjectsOnStart(.failure), isTrue);
      expect(pullRequestAgentWatchInjectsOnStart(.none), isFalse);
      expect(pullRequestAgentWatchInjectsOnStart(.pending), isFalse);
      expect(pullRequestAgentWatchInjectsOnStart(.success), isFalse);
    });
  });

  group('evaluatePullRequestAgentWatch', () {
    test('dispatches once per failing head sha', () {
      final first = evaluatePullRequestAgentWatch(
        session: session,
        snapshot: PullRequestAgentWatchSnapshot(
          review: _review(),
          checksRollup: .failure,
        ),
      );
      expect(first.action, PullRequestAgentWatchAction.dispatchFix);
      expect(first.failureSignature, '42:abc123');

      final repeat = evaluatePullRequestAgentWatch(
        session: PullRequestAgentWatchSession(
          workspaceId: session.workspaceId,
          reviewNumber: session.reviewNumber,
          mode: session.mode,
          binding: session.binding,
          scope: session.scope,
          lastDispatchedFailureSignature: first.failureSignature,
        ),
        snapshot: PullRequestAgentWatchSnapshot(
          review: _review(),
          checksRollup: .failure,
        ),
      );
      expect(repeat.action, PullRequestAgentWatchAction.none);
    });

    test('merges a green open pull request in fix-and-merge mode', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: const PullRequestAgentWatchSession(
          workspaceId: 'workspace-1',
          reviewNumber: 42,
          mode: .fixAndMerge,
          binding: AgentTaskDispatchBinding(profileId: 'profile-1'),
          scope: scope,
        ),
        snapshot: PullRequestAgentWatchSnapshot(
          review: _review(mergeable: .mergeable),
          checksRollup: .success,
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.merge);
      expect(evaluation.headSha, 'abc123');
    });

    test('does not merge the same head sha twice', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: const PullRequestAgentWatchSession(
          workspaceId: 'workspace-1',
          reviewNumber: 42,
          mode: .fixAndMerge,
          binding: AgentTaskDispatchBinding(profileId: 'profile-1'),
          scope: scope,
          lastMergedHeadSha: 'abc123',
        ),
        snapshot: PullRequestAgentWatchSnapshot(
          review: _review(mergeable: .mergeable),
          checksRollup: .success,
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.none);
    });

    test('keeps the watch eligible after a failed dispatch or merge', () {
      const result = AgentTaskDispatchResult(
        workspaceId: 'workspace-1',
        tabId: 'tab-2',
        openedNewTab: true,
        label: 'Codex Builder',
        profileId: 'profile-1',
      );
      expect(
        identical(
          pullRequestAgentWatchAfterDispatch(
            session: session,
            result: null,
            failureSignature: '42:abc123',
          ),
          session,
        ),
        isTrue,
      );
      final dispatched = pullRequestAgentWatchAfterDispatch(
        session: session,
        result: result,
        failureSignature: '42:abc123',
      );
      expect(dispatched.lastDispatchedFailureSignature, '42:abc123');
      expect(dispatched.binding.tabId, 'tab-2');
      expect(
        identical(
          pullRequestAgentWatchAfterMerge(
            session: session,
            merged: false,
            headSha: 'abc123',
          ),
          session,
        ),
        isTrue,
      );
      expect(
        pullRequestAgentWatchAfterMerge(
          session: session,
          merged: true,
          headSha: 'abc123',
        ).lastMergedHeadSha,
        'abc123',
      );
    });

    test('keeps prior signatures when a successful result omits them', () {
      const prior = PullRequestAgentWatchSession(
        workspaceId: 'workspace-1',
        reviewNumber: 42,
        mode: .fixAndMerge,
        binding: AgentTaskDispatchBinding(tabId: 'tab-1'),
        scope: scope,
        lastDispatchedFailureSignature: '42:oldsha',
        lastMergedHeadSha: 'oldsha',
      );
      const result = AgentTaskDispatchResult(
        workspaceId: 'workspace-1',
        tabId: 'tab-2',
        openedNewTab: false,
        label: 'Codex',
      );
      expect(
        pullRequestAgentWatchAfterDispatch(
          session: prior,
          result: result,
          failureSignature: null,
        ).lastDispatchedFailureSignature,
        '42:oldsha',
      );
      expect(
        pullRequestAgentWatchAfterMerge(
          session: prior,
          merged: true,
          headSha: null,
        ).lastMergedHeadSha,
        'oldsha',
      );
    });

    test('stops when the pull request is merged or unlinked', () {
      expect(
        evaluatePullRequestAgentWatch(
          session: session,
          snapshot: PullRequestAgentWatchSnapshot(
            review: _review(state: .merged),
            checksRollup: .success,
          ),
        ).action,
        PullRequestAgentWatchAction.stop,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: session,
          snapshot: PullRequestAgentWatchSnapshot(
            review: _review(state: .closed),
            checksRollup: .failure,
          ),
        ).action,
        PullRequestAgentWatchAction.stop,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: session,
          snapshot: const PullRequestAgentWatchSnapshot(),
        ).action,
        PullRequestAgentWatchAction.stop,
      );
      expect(
        evaluatePullRequestAgentWatch(session: session, snapshot: null).action,
        PullRequestAgentWatchAction.none,
      );
    });
  });
}

HostedReview _review({
  HostedReviewState state = HostedReviewState.open,
  HostedReviewMergeable mergeable = HostedReviewMergeable.unknown,
}) {
  return HostedReview(
    provider: .github,
    number: 42,
    title: 'feat: example',
    state: state,
    url: 'https://github.com/leynier/alera/pull/42',
    headSha: 'abc123',
    mergeable: mergeable,
  );
}
