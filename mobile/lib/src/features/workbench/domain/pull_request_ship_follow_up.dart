import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';

/// What Ship starts once the pull request exists. Phone counterpart of the
/// desktop Ship split button.
enum PullRequestShipFollowUp {
  /// Ship only.
  none,

  /// Start Watch and Fix on the shipped pull request.
  watchAndFix,

  /// Start Watch, Fix and Merge on the shipped pull request. A draft can never
  /// merge, so this follow-up always ships a ready pull request.
  watchFixAndMerge;

  bool get watches => this != none;

  bool get merges => this == watchFixAndMerge;

  PullRequestAgentWatchMode? get watchMode => switch (this) {
    none => null,
    watchAndFix => PullRequestAgentWatchMode.fix,
    watchFixAndMerge => PullRequestAgentWatchMode.fixAndMerge,
  };

  String get label => switch (this) {
    none => 'Ship Only',
    watchAndFix => 'Watch and Fix',
    watchFixAndMerge => 'Watch, Fix and Merge',
  };

  static PullRequestShipFollowUp fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return none;
  }
}

/// Everything the Ship sheet submits. [binding] is the agent picked before
/// shipping when [followUp] watches.
typedef PullRequestShipRequest = ({
  MobilePullRequestShipInput input,
  PullRequestShipFollowUp followUp,
  PullRequestAgentWatchScope watchScope,
  AgentTaskDispatchBinding? binding,
});

/// What a submitted Ship reports. [error] means Ship failed and the form comes
/// back; [notice] means the pull request exists but a follow-up did not start,
/// and replaces the success message.
typedef PullRequestShipOutcome = ({String? error, String? notice});

/// Starts the watch [request] asks for on the pull request in [shipped].
/// Returns a message for the user when the pull request exists but the watch
/// could not start, and null otherwise.
Future<String?> startShippedPullRequestWatch({
  required PullRequestShipRequest request,
  required MobilePullRequestSnapshot? shipped,
  required Future<void> Function(
    int reviewNumber,
    PullRequestAgentWatchMode mode,
    AgentTaskDispatchBinding binding,
    MobilePullRequestSnapshot snapshot,
  )
  start,
}) async {
  final mode = request.followUp.watchMode;
  final binding = request.binding;
  if (mode == null || binding == null || shipped == null) {
    return null;
  }
  final review = shipped.review;
  if (review == null) {
    return 'The pull request was created, but watching could not start. '
        'Use Ask Agent on the pull request to watch it.';
  }
  try {
    await start(review.number, mode, binding, shipped);
    return null;
  } on Object catch (error) {
    return 'Pull request #${review.number} was created, but watching could '
        'not start. $error';
  }
}
