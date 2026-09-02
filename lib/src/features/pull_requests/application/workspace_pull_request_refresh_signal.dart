import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_refresh_signal.g.dart';

/// Lightweight invalidation signal shared by PR mutations and the global
/// sidebar monitor. Reading this provider never initializes settings, storage,
/// git, or forge dependencies.
@Riverpod(keepAlive: true)
class WorkspacePullRequestRefreshSignal
    extends _$WorkspacePullRequestRefreshSignal {
  @override
  int build() => 0;

  void requestRefresh() => state++;
}
