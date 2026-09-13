import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_action_controller.g.dart';

final Logger _logger = Logger('PullRequestActionController');

/// Whether the paired runtime accepts `mobile.pullRequest.*` writes. False on
/// an older runtime, which keeps the panel read-only.
@riverpod
Future<bool> pullRequestActionsSupported(Ref ref, String hostId) async {
  final client = await ref.watch(workspaceClientProvider(hostId).future);
  return switch (client) {
    final MobilePullRequestActionsClient actions =>
      actions.supportsPullRequestActions,
    _ => false,
  };
}

/// The pull request write in flight for one workspace, or null when idle.
///
/// Kept alive so a merge started just before the user leaves the panel still
/// lands its snapshot and still reports a failure: the panel and its sheets
/// can be disposed while GitHub answers.
@Riverpod(keepAlive: true)
class PullRequestActionController extends _$PullRequestActionController {
  @override
  PullRequestActionKind? build(String hostId, String workspaceId) => null;

  /// Runs [action] and answers with the error to show, or null on success.
  Future<String?> run(
    PullRequestActionKind kind,
    Future<MobilePullRequestSnapshot> Function(
      MobilePullRequestActionsClient client,
    )
    action,
  ) async {
    if (state != null) {
      return 'Another pull request action is already running.';
    }
    state = kind;
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client case final MobilePullRequestActionsClient actions
          when actions.supportsPullRequestActions) {
        final snapshot = await action(actions);
        final panel = pullRequestControllerProvider(hostId, workspaceId);
        if (ref.exists(panel)) {
          ref.read(panel.notifier).applySnapshot(snapshot);
        }
        return null;
      }
      throw UnsupportedError(
        'Update the paired Alera runtime to change pull requests.',
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('Pull request ${kind.name} failed.', error, stackTrace);
      return pullRequestActionErrorMessage(error);
    } finally {
      state = null;
    }
  }
}
