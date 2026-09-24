import 'package:alera_mobile/src/features/runtime/domain/project_checkout_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_checkout_selection.g.dart';

@riverpod
class WorkspaceCheckoutSelection extends _$WorkspaceCheckoutSelection {
  @override
  String? build(String runtimeHostId, String? initialCheckoutHostId) =>
      initialCheckoutHostId;

  void select(String? hostId) => state = hostId == 'local' ? null : hostId;
}

@riverpod
Future<List<ProjectCheckoutSummary>> workspaceCheckoutOptions(
  Ref ref,
  String runtimeHostId,
  String projectId,
) async {
  final client = await ref.watch(workspaceClientProvider(runtimeHostId).future);
  if (client is! MobileCheckoutCatalogClient) {
    return const [ProjectCheckoutSummary(hostId: 'local', path: '')];
  }
  return (client as MobileCheckoutCatalogClient).listProjectCheckouts(
    projectId,
  );
}

@riverpod
class PromptLocalAttachments extends _$PromptLocalAttachments {
  @override
  Set<String> build(String runtimeHostId, Set<String> initialPaths) =>
      initialPaths;

  void add(String path) => state = Set.unmodifiable({...state, path});
}
