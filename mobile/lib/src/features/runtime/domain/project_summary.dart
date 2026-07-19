import 'package:alera_mobile/src/core/json_payload_fields.dart';

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.repoPath,
    this.kind = 'gitRepository',
    this.updatedAt,
  });

  final String id;
  final String name;
  final String repoPath;
  final String kind;
  final DateTime? updatedAt;

  factory ProjectSummary.fromJson(Map<String, Object?> json) {
    return ProjectSummary(
      id: json.requiredString('id'),
      name: json.requiredString('name'),
      repoPath: json.requiredString('repoPath'),
      kind: json.optionalString('kind') ?? 'gitRepository',
      updatedAt: json.optionalDateTime('updatedAt'),
    );
  }
}

class ProjectBranches {
  const ProjectBranches({
    required this.projectId,
    required this.branches,
    required this.localBranches,
  });

  final String projectId;
  final List<String> branches;
  final List<String> localBranches;

  factory ProjectBranches.fromJson(Map<String, Object?> json) {
    return ProjectBranches(
      projectId: json.requiredString('projectId'),
      branches: json.stringList('branches'),
      localBranches: json.stringList('localBranches'),
    );
  }
}
