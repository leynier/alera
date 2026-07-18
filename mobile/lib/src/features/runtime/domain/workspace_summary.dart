import 'package:alera_mobile/src/core/json_payload_fields.dart';

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.projectId,
    required this.name,
    required this.path,
    this.branch,
  });

  final String id;
  final String projectId;
  final String name;
  final String path;
  final String? branch;

  factory WorkspaceSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceSummary(
      id: json.requiredString('id'),
      projectId: json.requiredString('projectId'),
      name: json.requiredString('name'),
      path: json.requiredString('path'),
      branch: json.optionalString('branch'),
    );
  }
}
