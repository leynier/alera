import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_follow_up.dart';

/// The watch mode [followUp] starts, or null when it only ships.
PullRequestAgentWatchMode? pullRequestShipWatchMode(
  PullRequestShipFollowUp followUp,
) => switch (followUp) {
  PullRequestShipFollowUp.none => null,
  PullRequestShipFollowUp.watchAndFix => PullRequestAgentWatchMode.fix,
  PullRequestShipFollowUp.watchFixAndMerge =>
    PullRequestAgentWatchMode.fixAndMerge,
};

/// Ships, then starts the watch [followUp] asks for on the new pull request.
///
/// The agent is chosen before shipping, so the long ship runs without a dialog
/// in the middle and declining the choice commits nothing. A watch stops
/// itself while the panel shows no matching review, so it only starts once
/// [reloadReviewNumber] reports the shipped pull request.
Future<void> runPullRequestShipFollowUp({
  required PullRequestShipFollowUp followUp,
  required Future<AgentTaskDispatchBinding?> Function(
    PullRequestAgentWatchMode mode,
  )
  chooseAgent,
  required Future<CreateReviewResult> Function() ship,
  required Future<int?> Function() reloadReviewNumber,
  required Future<void> Function(
    int reviewNumber,
    PullRequestAgentWatchMode mode,
    AgentTaskDispatchBinding binding,
  )
  startWatch,
  required void Function(String message) onWatchFailed,
}) async {
  final mode = pullRequestShipWatchMode(followUp);
  if (mode == null) {
    await ship();
    return;
  }
  final binding = await chooseAgent(mode);
  if (binding == null) {
    return;
  }
  final result = await ship();
  if (result is! CreateReviewSuccess) {
    return;
  }
  final number = result.review.number;
  final failure =
      'Pull request #$number was created, but watching could not start.';
  if (await reloadReviewNumber() != number) {
    onWatchFailed('$failure Use Ask Agent on the pull request to watch it.');
    return;
  }
  try {
    await startWatch(number, mode, binding);
  } on Object catch (error) {
    onWatchFailed('$failure $error');
  }
}
