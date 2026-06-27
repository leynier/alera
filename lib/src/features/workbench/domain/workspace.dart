import 'package:dart_mappable/dart_mappable.dart';

part 'workspace.mapper.dart';

@MappableEnum()
enum WorkspaceKind { main, linked }

@MappableEnum()
enum WorkspaceStatus { active, removed }

@MappableClass()
class Workspace with WorkspaceMappable {
  const Workspace({
    required this.id,
    required this.projectId,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.updatedAt,
    required this.kind,
    required this.status,
    this.branch,
    this.sourceBranch,
    this.reusesExistingBranch = false,
  });

  final String id;
  final String projectId;
  final String name;
  final String? branch;
  final String path;
  final DateTime createdAt;
  final DateTime updatedAt;
  final WorkspaceKind kind;
  final WorkspaceStatus status;
  final String? sourceBranch;
  final bool reusesExistingBranch;

  bool get isMain => kind == WorkspaceKind.main;

  bool get isActive => status == WorkspaceStatus.active;

  factory Workspace.fromJson(Map<String, Object?> json) =>
      WorkspaceMapper.fromMap(Map<String, dynamic>.from(json));
}
