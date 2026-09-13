import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_control_branches.g.dart';

/// Branches for the branch sheet, loaded each time the sheet opens.
@riverpod
Future<MobileGitBranches> sourceControlBranches(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final client = await ref.watch(workspaceClientProvider(hostId).future);
  if (client case final MobileWorkspacePanelsClient panels
      when panels.supportsSourceControlWrites) {
    return panels.gitBranches(workspaceId);
  }
  throw UnsupportedError('Update the paired Alera runtime to switch branches.');
}
