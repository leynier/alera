import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Field casing mirrors the desktop runtime parsers in
/// `lib/src/features/workbench/infra/runtime_workbench_repository.dart`.
class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.projectId,
    required this.name,
    required this.path,
    this.branch,
    this.kind = 'linked',
    this.status = 'active',
    this.isPinned = false,
    this.parentWorkspaceId,
    this.childCount = 0,
    this.tagIds = const <String>[],
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String name;
  final String path;
  final String? branch;
  final String kind;
  final String status;
  final bool isPinned;
  final String? parentWorkspaceId;
  final int childCount;
  final List<String> tagIds;
  final DateTime? updatedAt;

  bool get isMain => kind == 'main';
  bool get hasParent => parentWorkspaceId != null;

  factory WorkspaceSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceSummary(
      id: json.requiredString('id'),
      projectId: json.requiredString('projectId'),
      name: json.requiredString('name'),
      path: json.requiredString('path'),
      branch: json.optionalString('branch'),
      kind: json.optionalString('kind') ?? 'linked',
      status: json.optionalString('status') ?? 'active',
      isPinned: json['isPinned'] == true,
      parentWorkspaceId: json.optionalString('parentWorkspaceId'),
      childCount: (json['childCount'] as num?)?.toInt() ?? 0,
      tagIds: json.stringList('tagIds'),
      updatedAt: json.optionalDateTime('updatedAt'),
    );
  }
}
