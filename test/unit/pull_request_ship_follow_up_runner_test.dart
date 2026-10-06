import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_ship_follow_up_runner.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_follow_up.dart';
import 'package:flutter_test/flutter_test.dart';

const _binding = AgentTaskDispatchBinding(tabId: 'tab-1', label: 'Codex');

const _shipped = CreateReviewSuccess(
  HostedReview(
    provider: .github,
    number: 42,
    title: 'feat: ship',
    state: .open,
    url: 'https://github.com/leynier/alera/pull/42',
    author: 'leynier',
    baseBranch: 'main',
    headBranch: 'feat/ship',
  ),
);

class _Run {
  final List<String> events = <String>[];
  final List<String> failures = <String>[];
  PullRequestAgentWatchMode? chosenMode;
  ({
    int number,
    PullRequestAgentWatchMode mode,
    AgentTaskDispatchBinding binding,
  })?
  started;

  Future<void> call(
    PullRequestShipFollowUp followUp, {
    AgentTaskDispatchBinding? binding = _binding,
    CreateReviewResult result = _shipped,
    int? reloadedNumber = 42,
    Object? startError,
  }) {
    return runPullRequestShipFollowUp(
      followUp: followUp,
      chooseAgent: (mode) async {
        events.add('choose');
        chosenMode = mode;
        return binding;
      },
      ship: () async {
        events.add('ship');
        return result;
      },
      reloadReviewNumber: () async {
        events.add('reload');
        return reloadedNumber;
      },
      startWatch: (number, mode, binding) async {
        events.add('watch');
        if (startError != null) {
          throw startError;
        }
        started = (number: number, mode: mode, binding: binding);
      },
      onWatchFailed: failures.add,
    );
  }
}

void main() {
  test('maps each follow-up to its watch mode', () {
    expect(pullRequestShipWatchMode(.none), isNull);
    expect(
      pullRequestShipWatchMode(.watchAndFix),
      PullRequestAgentWatchMode.fix,
    );
    expect(
      pullRequestShipWatchMode(.watchFixAndMerge),
      PullRequestAgentWatchMode.fixAndMerge,
    );
  });

  test('ship only never asks for an agent', () async {
    final run = _Run();
    await run(.none);
    expect(run.events, <String>['ship']);
  });

  test(
    'picks the agent before shipping, then watches the new pull request',
    () async {
      final run = _Run();
      await run(.watchFixAndMerge);
      expect(run.events, <String>['choose', 'ship', 'reload', 'watch']);
      expect(run.chosenMode, PullRequestAgentWatchMode.fixAndMerge);
      expect(run.started?.number, 42);
      expect(run.started?.mode, PullRequestAgentWatchMode.fixAndMerge);
      expect(run.started?.binding, same(_binding));
      expect(run.failures, isEmpty);
    },
  );

  test('declining the agent ships nothing', () async {
    final run = _Run();
    await run(.watchAndFix, binding: null);
    expect(run.events, <String>['choose']);
  });

  test('a failed ship starts no watch', () async {
    final run = _Run();
    await run(
      .watchAndFix,
      result: const CreateReviewFailure(code: .unknown, message: 'boom'),
    );
    expect(run.events, <String>['choose', 'ship']);
    expect(run.failures, isEmpty);
  });

  test(
    'reports instead of watching when the panel misses the pull request',
    () async {
      final run = _Run();
      await run(.watchAndFix, reloadedNumber: null);
      expect(run.events, <String>['choose', 'ship', 'reload']);
      expect(run.failures.single, contains('#42 was created'));
      expect(run.failures.single, contains('Ask Agent'));
    },
  );

  test('reports a watch that fails to start', () async {
    final run = _Run();
    await run(.watchAndFix, startError: StateError('host down'));
    expect(run.events, <String>['choose', 'ship', 'reload', 'watch']);
    expect(run.failures.single, contains('host down'));
  });
}
