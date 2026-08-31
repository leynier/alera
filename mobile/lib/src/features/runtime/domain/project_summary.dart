import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const ProjectSummary({
  required final String id,
  required final String name,
  required final String repoPath,
  final String kind = 'gitRepository',
  final DateTime? updatedAt,
}) {
  bool get supportsLinkedWorkspaces => kind == 'gitRepository';

  factory fromJson(Map<String, Object?> json) {
    return ProjectSummary(
      id: json.requiredString('id'),
      name: json.requiredString('name'),
      repoPath: json.requiredString('repoPath'),
      kind: json.optionalString('kind') ?? 'gitRepository',
      updatedAt: json.optionalDateTime('updatedAt'),
    );
  }
}

class const ProjectBranches({
  required final String projectId,
  required final List<String> branches,
  required final List<String> localBranches,
}) {
  factory fromJson(Map<String, Object?> json) {
    return ProjectBranches(
      projectId: json.requiredString('projectId'),
      branches: json.stringList('branches'),
      localBranches: json.stringList('localBranches'),
    );
  }
}
