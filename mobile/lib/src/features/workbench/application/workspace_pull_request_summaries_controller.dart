import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_pull_request_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_summaries_controller.g.dart';

/// Every workspace row indicator on one host. Refreshed when the runtime
/// reports topology or link changes; a transient failure keeps the last
/// snapshot so the rows do not blink empty between polls.
@Riverpod(keepAlive: true)
class WorkspacePullRequestSummariesController
    extends _$WorkspacePullRequestSummariesController {
  static const Set<String> _refreshEvents = <String>{
    'workspacesChanged',
    'linkedReviewsChanged',
  };

  @override
  Future<Map<String, MobileWorkspacePullRequestSummary>> build(
    String hostId,
  ) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client is! MobileWorkspacePullRequestSummariesClient) {
      return const <String, MobileWorkspacePullRequestSummary>{};
    }
    final summaries = client as MobileWorkspacePullRequestSummariesClient;
    if (!summaries.supportsPullRequestSummaries) {
      return const <String, MobileWorkspacePullRequestSummary>{};
    }
    if (ref.mounted) {
      final subscription = client.events.listen((event) {
        if (ref.mounted && _refreshEvents.contains(event.name)) {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(subscription.cancel);
    }
    try {
      final fresh = await summaries.pullRequestSummaries();
      return fresh.mergedOver(
        state.value ?? const <String, MobileWorkspacePullRequestSummary>{},
      );
    } on Object catch (error, stackTrace) {
      Logger('WorkspacePullRequestSummariesController')
          .warning('Could not load pull request summaries', error, stackTrace);
      return state.value ?? const <String, MobileWorkspacePullRequestSummary>{};
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
