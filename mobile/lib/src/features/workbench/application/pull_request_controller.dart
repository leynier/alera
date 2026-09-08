import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_controller.g.dart';

@riverpod
class PullRequestController extends _$PullRequestController {
  @override
  Future<MobilePullRequestSnapshot> build(
    String hostId,
    String workspaceId,
  ) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsPullRequests) {
      return panels.pullRequestSnapshot(workspaceId);
    }
    throw UnsupportedError(
      'Update the paired Alera runtime to review pull requests.',
    );
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(hostId, workspaceId));
  }
}
