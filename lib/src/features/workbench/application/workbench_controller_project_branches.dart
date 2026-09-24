part of 'workbench_controller.dart';

mixin _WorkbenchControllerProjectBranches on _$WorkbenchController {
  Future<ProjectBranchCatalog> loadHostBranchCatalog(
    Project project,
    String? hostId,
  ) {
    return RuntimeProjectBranchClient((verb, payload) async {
      await ref.read(runtimeStateMigrationProvider).ensureMigrated();
      return ref.read(runtimeHostClientProvider).runtimeRequest(verb, payload);
    }).load(project.id, hostId);
  }
}
