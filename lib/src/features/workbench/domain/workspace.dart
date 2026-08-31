import 'package:dart_mappable/dart_mappable.dart';

part 'workspace.mapper.dart';

@MappableEnum()
enum WorkspaceKind { main, linked }

@MappableEnum()
enum WorkspaceStatus { active, removed }

@MappableClass()
class const Workspace({
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
  this.instanceId,
  this.hostId = 'local',
  this.isPinned = false,
  this.tagIds = const <String>[],
  this.tagNames = const <String>[],
  this.sectionId,
  this.parentWorkspaceId,
  this.childCount = 0,
  this.workflowOwned = false,
}) with WorkspaceMappable {
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
  final String? instanceId;
  final String hostId;
  final bool isPinned;
  final List<String> tagIds;
  final List<String> tagNames;
  final String? sectionId;
  final String? parentWorkspaceId;
  final int childCount;

  /// Runtime-derived ownership on project workspace snapshots.
  final bool workflowOwned;

  bool get isMain => kind == WorkspaceKind.main;

  bool get isActive => status == WorkspaceStatus.active;

  bool get hasParentWorkspace => parentWorkspaceId?.trim().isNotEmpty ?? false;

  factory fromJson(Map<String, Object?> json) =>
      WorkspaceMapper.fromMap(Map<String, dynamic>.from(json));
}
