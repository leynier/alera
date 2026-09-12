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

  /// Shows the snapshot a write answered with, without another round trip.
  void apply(MobileGitStatusSnapshot snapshot) {
    state = AsyncData(snapshot);
  }

  /// Refreshes in place. Riverpod keeps the previous snapshot on a rebuild,
  /// so the panel keeps its list on screen instead of blanking to a spinner.
  Future<void> reload() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // The failure is already on `state`, next to the previous snapshot.
    }
  }
}
