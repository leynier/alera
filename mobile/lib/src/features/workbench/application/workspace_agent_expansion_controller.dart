import 'package:alera_mobile/src/features/workbench/infra/local_workspace_agent_expansion_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_agent_expansion_controller.g.dart';

@Riverpod(keepAlive: true)
LocalWorkspaceAgentExpansionRepository workspaceAgentExpansionRepository(
  Ref ref,
) {
  return LocalWorkspaceAgentExpansionRepository();
}

@riverpod
class WorkspaceAgentExpansionController
    extends _$WorkspaceAgentExpansionController {
  @override
  Future<Set<String>> build(String hostId) {
    return ref.watch(workspaceAgentExpansionRepositoryProvider).load(hostId);
  }

  Future<void> toggle(String workspaceId) async {
    final current = await future;
    final next = <String>{...current};
    if (!next.remove(workspaceId)) {
      next.add(workspaceId);
    }
    state = AsyncData(next);
    await ref
        .read(workspaceAgentExpansionRepositoryProvider)
        .save(hostId, next);
  }
}
