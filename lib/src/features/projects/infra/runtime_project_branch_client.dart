import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';

class RuntimeProjectBranchClient(
  final Future<Object?> Function(String, Map<String, Object?>) request,
) {
  Future<ProjectBranchCatalog> load(String projectId, String? hostId) async {
    final owner = hostId == null || hostId.trim().isEmpty ? 'local' : hostId;
    final value = await request('project.branches.list', {
      'projectId': projectId,
      'hostId': owner,
    });
    if (value is! Map ||
        value['projectId'] != projectId ||
        value['hostId'] != owner ||
        value['branches'] is! List ||
        value['localBranches'] is! List) {
      throw StateError(
        'Update the runtime to load branches from the selected host.',
      );
    }
    return ProjectBranchCatalog(
      projectId: projectId,
      hostId: owner,
      branches: List<String>.unmodifiable(value['branches'] as List),
      localBranches: Set<String>.unmodifiable(
        (value['localBranches'] as List).cast<String>(),
      ),
    );
  }
}
