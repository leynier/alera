import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_watch_controller.g.dart';

/// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.
@riverpod
class PullRequestWatchController extends _$PullRequestWatchController {
  @override
  Future<MobilePullRequestWatchSnapshot> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client is! MobilePullRequestWatchClient ||
        !(client as MobilePullRequestWatchClient).supportsPullRequestWatch) {
      return const MobilePullRequestWatchSnapshot();
    }
    final watches = client as MobilePullRequestWatchClient;
    final subscription = client.events.listen((event) {
      if (ref.mounted && event.name == 'pullRequestWatchChanged') {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    final items = await watches.listPullRequestWatches();
    return MobilePullRequestWatchSnapshot(
      supported: true,
      byWorkspace: <String, MobilePullRequestWatch>{
        for (final watch in items) watch.workspaceId: watch,
      },
    );
  }
}
