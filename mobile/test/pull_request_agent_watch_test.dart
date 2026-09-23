import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = PullRequestAgentWatchSession(
  hostId: 'host-1',
  workspaceId: 'workspace-1',
  reviewNumber: 42,
  mode: PullRequestAgentWatchMode.fix,
  binding: AgentTaskDispatchBinding(tabId: 'tab-1'),
);

void main() {
  test('parses additive headSha and outdated fields', () {
    final review = MobilePullRequestReview.fromJson(<String, Object?>{
      'number': 7,
      'title': 'feat',
      'state': 'OPEN',
      'url': 'https://github.com/leynier/alera/pull/7',
      'headSha': 'abc123',
      'comments': <Object?>[
        <String, Object?>{
          'id': 1,
          'kind': 'review',
          'threadId': 'T1',
          'outdated': true,
        },
      ],
    });
    expect(review.headSha, 'abc123');
    expect(review.comments.single.outdated, isTrue);
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
    expect(PullRequestAgentWatchScope.fromJson(none.toJson()), none);
  });

  test('labels both watch modes', () {
    expect(
      pullRequestAgentWatchModeLabel(PullRequestAgentWatchMode.fix),
      'Watching: Fix',
    );
    expect(
      pullRequestAgentWatchModeLabel(PullRequestAgentWatchMode.fixAndMerge),
      'Watching: Fix and Merge',
    );
  });

  group('pullRequestAgentWatchConcerns', () {
    test('collects every concern inside the scope', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: _snapshot(
          rollup: PullRequestChecksRollup.failure,
          mergeable: 'CONFLICTING',
          comments: <MobilePullRequestComment>[_thread('T1')],
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
        snapshot: _snapshot(
          rollup: PullRequestChecksRollup.failure,
          mergeable: 'CONFLICTING',
          comments: <MobilePullRequestComment>[_thread('T1')],
        ),
        scope: const PullRequestAgentWatchScope(
          checks: false,
          comments: false,
          conflicts: false,
        ),
      );
      expect(concerns.isEmpty, isTrue);
    });

    test('does not treat unknown mergeability as a conflict', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: _snapshot(mergeable: 'UNKNOWN'),
        scope: PullRequestAgentWatchScope.defaults,
      );
      expect(concerns.conflict, isFalse);
    });

    test('skips threads written only by the pull request author', () {
      final concerns = pullRequestAgentWatchConcerns(
        snapshot: _snapshot(
          comments: <MobilePullRequestComment>[
            _thread('T1', author: 'leynier'),
          ],
        ),
        scope: PullRequestAgentWatchScope.defaults,
      );
      expect(concerns.isEmpty, isTrue);
    });

    test('drops a thread only when every comment is outdated', () {
      expect(
        pendingReviewThreads(
          comments: <MobilePullRequestComment>[
            _thread('T1', outdated: true),
            _thread('T1', outdated: false, author: 'leynier'),
          ],
        ),
        isNotEmpty,
      );
      expect(
        pendingReviewThreads(
          comments: <MobilePullRequestComment>[
            _thread('T1', outdated: true),
            _thread('T1', outdated: true, author: 'leynier'),
          ],
        ),
        isEmpty,
      );
    });
  });

  test('cancelled checks fail the rollup', () {
    expect(
      derivePullRequestChecksRollup(const <MobilePullRequestCheck>[
        MobilePullRequestCheck(name: 'build', bucket: 'pass'),
        MobilePullRequestCheck(name: 'lint', bucket: 'cancel'),
      ]),
      PullRequestChecksRollup.failure,
    );
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

  group('evaluatePullRequestAgentWatch', () {
    test('dispatches once per failing head sha', () {
      final snapshot = _snapshot(rollup: PullRequestChecksRollup.failure);
      final first = evaluatePullRequestAgentWatch(
        session: _session,
        snapshot: snapshot,
      );
      expect(first.action, PullRequestAgentWatchAction.dispatch);

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
          snapshot: _snapshot(
            rollup: PullRequestChecksRollup.failure,
            headSha: 'def456',
          ),
        ).action,
        PullRequestAgentWatchAction.dispatch,
      );
    });

    test('merges a green open pull request in fix-and-merge mode', () {
      final evaluation = evaluatePullRequestAgentWatch(
        session: _mergeSession(),
        snapshot: _snapshot(
          rollup: PullRequestChecksRollup.success,
          mergeable: 'MERGEABLE',
        ),
      );
      expect(evaluation.action, PullRequestAgentWatchAction.merge);
      expect(evaluation.headSha, 'abc123');
    });

    test('does not merge a draft', () {
      expect(
        evaluatePullRequestAgentWatch(
          session: _mergeSession(),
          snapshot: _snapshot(
            rollup: PullRequestChecksRollup.success,
            mergeable: 'MERGEABLE',
            isDraft: true,
          ),
        ).action,
        PullRequestAgentWatchAction.none,
      );
    });

    test('waits for complete comments before merging passing checks', () {
      expect(
        evaluatePullRequestAgentWatch(
          session: _mergeSession(),
          snapshot: _snapshot(
            rollup: PullRequestChecksRollup.success,
            mergeable: 'MERGEABLE',
            commentsComplete: false,
          ),
        ).action,
        PullRequestAgentWatchAction.none,
      );
    });

    test('stops when the pull request is merged or unlinked', () {
      expect(
        evaluatePullRequestAgentWatch(
          session: _session,
          snapshot: _snapshot(state: 'MERGED'),
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
    });
  });
}

PullRequestAgentWatchSession _mergeSession({String? lastMergedHeadSha}) {
  return PullRequestAgentWatchSession(
    hostId: 'host-1',
    workspaceId: 'workspace-1',
    reviewNumber: 42,
    mode: PullRequestAgentWatchMode.fixAndMerge,
    binding: const AgentTaskDispatchBinding(profileId: 'profile-1'),
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
    result: const AgentTaskDispatchResult(
      tabId: 'tab-2',
      openedNewTab: true,
      label: 'Codex',
      profileId: 'profile-1',
    ),
    concerns: evaluation.concerns,
    headSha: evaluation.headSha,
  );
}

PullRequestAgentWatchSnapshot _snapshot({
  String state = 'OPEN',
  bool isDraft = false,
  String mergeable = 'UNKNOWN',
  PullRequestChecksRollup rollup = PullRequestChecksRollup.none,
  String headSha = 'abc123',
  List<MobilePullRequestComment> comments = const <MobilePullRequestComment>[],
  bool commentsComplete = true,
}) {
  return PullRequestAgentWatchSnapshot(
    review: MobilePullRequestReview(
      number: 42,
      title: 'feat: example',
      state: state,
      url: 'https://github.com/leynier/alera/pull/42',
      author: 'leynier',
      isDraft: isDraft,
      mergeable: mergeable,
      headSha: headSha,
    ),
    checksRollup: rollup,
    comments: comments,
    commentsComplete: commentsComplete,
  );
}

MobilePullRequestComment _thread(
  String id, {
  String author = 'pullfrog',
  bool resolved = false,
  bool outdated = false,
}) {
  return MobilePullRequestComment(
    id: 1,
    author: author,
    body: 'Remove the unused alias.',
    kind: 'review',
    path: 'lib/a.dart',
    line: 3,
    resolved: resolved,
    outdated: outdated,
    threadId: id,
  );
}
