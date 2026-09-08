import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_control_controller.g.dart';

@riverpod
class SourceControlController extends _$SourceControlController {
  @override
  Future<MobileGitStatusSnapshot> build(
    String hostId,
    String workspaceId,
  ) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsSourceControl) {
      return panels.gitStatus(workspaceId);
    }
    throw UnsupportedError(
      'Update the paired Alera runtime to review source control.',
    );
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(hostId, workspaceId));
  }
}
