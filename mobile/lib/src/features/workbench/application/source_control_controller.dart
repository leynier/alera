import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
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
    // Only the root matters here; toggling ignored files must not re-run git.
    final savedRoot = await ref.watch(
      explorerPreferencesControllerProvider(
        hostId,
        workspaceId,
      ).selectAsync((preferences) => preferences.sourceControlRoot),
    );
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsSourceControl) {
      return panels.gitStatus(
        workspaceId,
        relativeRoot: activeSourceControlRoot(panels, savedRoot),
      );
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

/// The saved root, or none when this host cannot honor one. A root chosen
/// against a newer runtime must not break Source Control after pairing with
/// an older one.
String activeSourceControlRoot(
  MobileWorkspacePanelsClient panels,
  String? savedRoot,
) {
  return panels.supportsSourceControlRoot ? savedRoot ?? '' : '';
}
