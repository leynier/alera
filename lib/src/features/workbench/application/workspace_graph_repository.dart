import 'package:uuid/uuid.dart';

class const WorkspaceTag({
  required final String id,
  required final String name,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final String? color,
}) {
  factory create({
    required String name,
    String color = defaultColor,
    DateTime? now,
    Uuid uuid = const Uuid(),
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return WorkspaceTag(
      id: uuid.v4(),
      name: name.trim(),
      color: color,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory fromJson(Map<String, Object?> json) {
    return WorkspaceTag(
      id: json['id'] as String,
      name: json['name'] as String,
      color: _emptyToNull(json['color']),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  static const String defaultColor = '#3b82f6';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'color': color,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class const WorkspaceRelation({
  required final String id,
  required final String parentWorkspaceId,
  required final String parentInstanceId,
  required final String childWorkspaceId,
  required final String childInstanceId,
  required final DateTime createdAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    return WorkspaceRelation(
      id: json['id'] as String,
      parentWorkspaceId: json['parentWorkspaceId'] as String,
      parentInstanceId: json['parentInstanceId'] as String,
      childWorkspaceId: json['childWorkspaceId'] as String,
      childInstanceId: json['childInstanceId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }
}

abstract interface class WorkspaceGraphRepository {
  Future<List<WorkspaceTag>> listTags();

  Future<WorkspaceTag> upsertTag(WorkspaceTag tag);

  Future<void> removeTag(String tagId);

  Future<void> assignTag({required String workspaceId, required String tagId});

  Future<void> unassignTag({
    required String workspaceId,
    required String tagId,
  });

  Future<List<WorkspaceRelation>> listRelations();

  Future<WorkspaceRelation> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  });

  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  });
}

/// Collects every workspace reachable through child relations starting from
/// [workspaceId]. Used to keep parent selection acyclic.
Set<String> workspaceDescendantIds(
  String workspaceId,
  List<WorkspaceRelation> relations,
) {
  final childrenByParent = <String, List<String>>{};
  for (final relation in relations) {
    childrenByParent
        .putIfAbsent(relation.parentWorkspaceId, () => <String>[])
        .add(relation.childWorkspaceId);
  }
  final descendants = <String>{};
  void visit(String parentId) {
    for (final childId in childrenByParent[parentId] ?? const <String>[]) {
      if (descendants.add(childId)) {
        visit(childId);
      }
    }
  }

  visit(workspaceId);
  return descendants;
}

String? _emptyToNull(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}
