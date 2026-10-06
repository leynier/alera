import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_ship_follow_up.dart';
import 'package:flutter_test/flutter_test.dart';

const _binding = AgentTaskDispatchBinding(tabId: 'tab-1');

PullRequestShipRequest _request(
  PullRequestShipFollowUp followUp, {
  AgentTaskDispatchBinding? binding = _binding,
}) => (
  input: (baseBranch: 'main', draft: false, stagedOnly: true),
  followUp: followUp,
  watchScope: PullRequestAgentWatchScope.defaults,
  binding: binding,
);

MobilePullRequestSnapshot _shipped({bool withReview = true}) =>
    MobilePullRequestSnapshot.fromJson(<String, Object?>{
      'branch': 'feat/ship',
      'provider': 'github',
      if (withReview)
        'review': <String, Object?>{
          'number': 42,
          'title': 'feat: ship',
          'state': 'open',
          'url': 'https://github.com/leynier/alera/pull/42',
        },
    });

void main() {
  test('maps follow-ups to watch modes and names', () {
    expect(PullRequestShipFollowUp.none.watchMode, isNull);
    expect(
      PullRequestShipFollowUp.watchAndFix.watchMode,
      PullRequestAgentWatchMode.fix,
    );
    expect(
      PullRequestShipFollowUp.watchFixAndMerge.watchMode,
      PullRequestAgentWatchMode.fixAndMerge,
    );
    expect(
      PullRequestShipFollowUp.fromName('watchFixAndMerge'),
      PullRequestShipFollowUp.watchFixAndMerge,
    );
    expect(
      PullRequestShipFollowUp.fromName('bogus'),
      PullRequestShipFollowUp.none,
    );
    expect(
      PullRequestShipFollowUp.fromName(null),
      PullRequestShipFollowUp.none,
    );
  });

  test('starts the chosen watch on the shipped pull request', () async {
    ({int number, PullRequestAgentWatchMode mode, String? tabId})? started;
    final message = await startShippedPullRequestWatch(
      request: _request(.watchFixAndMerge),
      shipped: _shipped(),
      start: (number, mode, binding, _) async {
        started = (number: number, mode: mode, tabId: binding.tabId);
      },
    );
    expect(message, isNull);
    expect(started?.number, 42);
    expect(started?.mode, PullRequestAgentWatchMode.fixAndMerge);
    expect(started?.tabId, 'tab-1');
  });

  test('ship only starts nothing', () async {
    var started = false;
    final message = await startShippedPullRequestWatch(
      request: _request(.none, binding: null),
      shipped: _shipped(),
      start: (_, _, _, _) async => started = true,
    );
    expect(message, isNull);
    expect(started, isFalse);
  });

  test('reports a shipped snapshot without a review', () async {
    final message = await startShippedPullRequestWatch(
      request: _request(.watchAndFix),
      shipped: _shipped(withReview: false),
      start: (_, _, _, _) async {},
    );
    expect(message, contains('Ask Agent'));
  });

  test('reports a watch that fails to start', () async {
    final message = await startShippedPullRequestWatch(
      request: _request(.watchAndFix),
      shipped: _shipped(),
      start: (_, _, _, _) async => throw StateError('runtime down'),
    );
    expect(message, contains('#42 was created'));
    expect(message, contains('runtime down'));
  });
}
