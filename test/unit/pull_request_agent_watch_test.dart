import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_request_agent_watch_fixtures.dart';

const _session = PullRequestAgentWatchSession(
  workspaceId: 'workspace-1',
  reviewNumber: 42,
  mode: .fix,
  binding: AgentTaskDispatchBinding(tabId: 'tab-1'),
  scope: pullRequestWatchTestScope,
);

void main() {
  group('evaluatePullRequestAgentWatch', () {
    test('dispatches once per failing head sha', () {
      final snapshot = pullRequestWatchSnapshot(rollup: .failure);
      final first = evaluatePullRequestAgentWatch(
        session: _session,
        snapshot: snapshot,
      );
      expect(first.action, PullRequestAgentWatchAction.dispatch);
      expect(first.concerns.checksFailed, isTrue);

      final dispatched = _afterDispatch(_session, first);
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: snapshot,
        ).action,
        PullRequestAgentWatchAction.none,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(
            rollup: .failure,
            headSha: 'def456',
          ),
        ).action,
        PullRequestAgentWatchAction.dispatch,
      );
    });

    test('does not repeat a check rerun on the same head sha', () {
      final dispatched = _afterDispatch(
        _session,
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: pullRequestWatchSnapshot(rollup: .failure),
        ),
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(rollup: .pending),
        ).action,
        PullRequestAgentWatchAction.none,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(rollup: .failure),
        ).action,
        PullRequestAgentWatchAction.none,
      );
    });

    test('dispatches for merge conflicts even when checks are green', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: _session,
        snapshot: pullRequestWatchSnapshot(
          rollup: .success,
          mergeable: .conflicting,
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.dispatch);
      expect(evaluation.concerns.conflict, isTrue);
      expect(evaluation.concerns.checksFailed, isFalse);

      final dispatched = _afterDispatch(_session, evaluation);
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(mergeable: .unknown),
        ).action,
        PullRequestAgentWatchAction.none,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(mergeable: .conflicting),
        ).action,
        PullRequestAgentWatchAction.none,
      );
    });

    test('dispatches for unresolved review threads', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: _session,
        snapshot: pullRequestWatchSnapshot(
          rollup: .success,
          comments: <ReviewComment>[
            pullRequestWatchThread('T1'),
            pullRequestWatchThread('T2'),
          ],
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.dispatch);
      expect(evaluation.concerns.threadIds, <String>{'T1', 'T2'});
    });

    test('dispatches again only when a new thread appears', () {
      final dispatched = _afterDispatch(
        _session,
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: pullRequestWatchSnapshot(
            comments: <ReviewComment>[
              pullRequestWatchThread('T1'),
              pullRequestWatchThread('T2'),
            ],
          ),
        ),
      );

      final resolvedOne = evaluatePullRequestAgentWatch(
        session: dispatched,
        snapshot: pullRequestWatchSnapshot(
          comments: <ReviewComment>[
            pullRequestWatchThread('T1', resolved: true),
            pullRequestWatchThread('T2'),
          ],
        ),
      );
      expect(resolvedOne.action, PullRequestAgentWatchAction.none);

      final newThread = evaluatePullRequestAgentWatch(
        session: dispatched,
        snapshot: pullRequestWatchSnapshot(
          comments: <ReviewComment>[
            pullRequestWatchThread('T1'),
            pullRequestWatchThread('T2'),
            pullRequestWatchThread('T3'),
          ],
        ),
      );
      expect(newThread.action, PullRequestAgentWatchAction.dispatch);
      expect(newThread.concerns.threadIds, <String>{'T1', 'T2', 'T3'});
    });

    test('adds a new concern on the same head sha', () {
      final dispatched = _afterDispatch(
        _session,
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: pullRequestWatchSnapshot(rollup: .failure),
        ),
      );
      final evaluation = evaluatePullRequestAgentWatch(
        session: dispatched,
        snapshot: pullRequestWatchSnapshot(
          rollup: .failure,
          mergeable: .conflicting,
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.dispatch);
      expect(evaluation.concerns.checksFailed, isTrue);
      expect(evaluation.concerns.conflict, isTrue);
    });

    test('ignores review threads outside the scope', () {
      const session = PullRequestAgentWatchSession(
        workspaceId: 'workspace-1',
        reviewNumber: 42,
        mode: .fixAndMerge,
        binding: AgentTaskDispatchBinding(profileId: 'profile-1'),
        scope: pullRequestWatchTestScope,
        watchScope: PullRequestAgentWatchScope(comments: false),
      );
      final evaluation = evaluatePullRequestAgentWatch(
        session: session,
        snapshot: pullRequestWatchSnapshot(
          rollup: .success,
          mergeable: .mergeable,
          comments: <ReviewComment>[pullRequestWatchThread('T1')],
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.merge);
    });

    test('merges a green open pull request in fix-and-merge mode', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: _mergeSession(),
        snapshot: pullRequestWatchSnapshot(
          rollup: .success,
          mergeable: .mergeable,
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.merge);
      expect(evaluation.headSha, 'abc123');
    });

    test('waits for pending review threads before merging', () {
      final dispatched = _afterDispatch(
        _mergeSession(),
        evaluatePullRequestAgentWatch(
          session: _mergeSession(),
          snapshot: pullRequestWatchSnapshot(
            rollup: .success,
            mergeable: .mergeable,
            comments: <ReviewComment>[pullRequestWatchThread('T1')],
          ),
        ),
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(
            rollup: .success,
            mergeable: .mergeable,
            comments: <ReviewComment>[pullRequestWatchThread('T1')],
          ),
        ).action,
        PullRequestAgentWatchAction.none,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: dispatched,
          snapshot: pullRequestWatchSnapshot(
            rollup: .success,
            mergeable: .mergeable,
            comments: <ReviewComment>[
              pullRequestWatchThread('T1', resolved: true),
            ],
          ),
        ).action,
        PullRequestAgentWatchAction.merge,
      );
    });

    test('does not merge the same head sha twice', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: _mergeSession(lastMergedHeadSha: 'abc123'),
        snapshot: pullRequestWatchSnapshot(
          rollup: .success,
          mergeable: .mergeable,
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.none);
    });

    test('stops when the pull request is merged or unlinked', () {
      expect(
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: pullRequestWatchSnapshot(state: .merged, rollup: .success),
        ).action,
        PullRequestAgentWatchAction.stop,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: pullRequestWatchSnapshot(state: .closed, rollup: .failure),
        ).action,
        PullRequestAgentWatchAction.stop,
      );
      expect(
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: const PullRequestAgentWatchSnapshot(),
        ).action,
        PullRequestAgentWatchAction.stop,
      );
      expect(
        evaluatePullRequestAgentWatch(session: _session, snapshot: null).action,
        PullRequestAgentWatchAction.none,
      );
    });
  });

  group('session updates', () {
    test('keeps the watch eligible after a failed dispatch or merge', () {
      const concerns = PullRequestAgentWatchConcerns(checksFailed: true);
      expect(
        identical(
          pullRequestAgentWatchAfterDispatch(
            session: _session,
            result: null,
            concerns: concerns,
            headSha: 'abc123',
          ),
          _session,
        ),
        isTrue,
      );
      final dispatched = pullRequestAgentWatchAfterDispatch(
        session: _session,
        result: pullRequestWatchTestDispatchResult,
        concerns: concerns,
        headSha: 'abc123',
      );
      expect(dispatched.lastDispatch?.headSha, 'abc123');
      expect(dispatched.lastDispatch?.checksFailed, isTrue);
      expect(dispatched.binding.tabId, 'tab-2');
      expect(
        identical(
          pullRequestAgentWatchAfterMerge(
            session: _session,
            merged: false,
            headSha: 'abc123',
          ),
          _session,
        ),
        isTrue,
      );
      expect(
        pullRequestAgentWatchAfterMerge(
          session: _session,
          merged: true,
          headSha: 'abc123',
        ).lastMergedHeadSha,
        'abc123',
      );
    });

    test('keeps prior values when a successful result omits them', () {
      const prior = PullRequestAgentWatchSession(
        workspaceId: 'workspace-1',
        reviewNumber: 42,
        mode: .fixAndMerge,
        binding: AgentTaskDispatchBinding(tabId: 'tab-1'),
        scope: pullRequestWatchTestScope,
        watchScope: PullRequestAgentWatchScope(conflicts: false),
        lastMergedHeadSha: 'oldsha',
      );
      final merged = pullRequestAgentWatchAfterMerge(
        session: prior,
        merged: true,
        headSha: null,
      );
      expect(merged.lastMergedHeadSha, 'oldsha');
      expect(merged.watchScope.conflicts, isFalse);
    });
  });
}

PullRequestAgentWatchSession _mergeSession({String? lastMergedHeadSha}) {
  return PullRequestAgentWatchSession(
    workspaceId: 'workspace-1',
    reviewNumber: 42,
    mode: .fixAndMerge,
    binding: const AgentTaskDispatchBinding(profileId: 'profile-1'),
    scope: pullRequestWatchTestScope,
    lastMergedHeadSha: lastMergedHeadSha,
  );
}

PullRequestAgentWatchSession _afterDispatch(
  PullRequestAgentWatchSession session,
  PullRequestAgentWatchEvaluation evaluation,
) {
  expect(evaluation.action, PullRequestAgentWatchAction.dispatch);
  return pullRequestAgentWatchAfterDispatch(
    session: session,
    result: pullRequestWatchTestDispatchResult,
    concerns: evaluation.concerns,
    headSha: evaluation.headSha,
  );
}
