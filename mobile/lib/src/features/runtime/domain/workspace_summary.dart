import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Field casing mirrors the desktop runtime parsers in
/// `lib/src/features/workbench/infra/runtime_workbench_repository.dart`.
class const WorkspaceSummary({
  required final String id,
  required final String projectId,
  required final String name,
  required final String path,
  final String? branch,
  final String kind = 'linked',
  final String status = 'active',
  final bool isPinned = false,
  final String? parentWorkspaceId,
  final int childCount = 0,
  final List<String> tagIds = const <String>[],
  final List<String> tagNames = const <String>[],
  final String? sourceBranch,
  final bool reusesExistingBranch = false,
  final DateTime? updatedAt,
}) {
  bool get isMain => kind == 'main';
  bool get hasParent => parentWorkspaceId != null;

  factory fromJson(Map<String, Object?> json) {
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
      tagNames: json.stringList('tagNames'),
      sourceBranch: json.optionalString('sourceBranch'),
      reusesExistingBranch: json['reusesExistingBranch'] == true,
      updatedAt: json.optionalDateTime('updatedAt'),
    );
  }
}
