import 'package:dart_mappable/dart_mappable.dart';

part 'workspace_section.mapper.dart';

@MappableClass()
class WorkspaceSection with WorkspaceSectionMappable {
  const WorkspaceSection({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WorkspaceSection.fromJson(Map<String, Object?> json) =>
      WorkspaceSectionMapper.fromMap(Map<String, dynamic>.from(json));
}
