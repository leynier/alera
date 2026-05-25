import 'package:dart_mappable/dart_mappable.dart';

part 'project.mapper.dart';

@MappableEnum()
enum ProjectKind { gitRepository, folder }

@MappableClass()
class Project with ProjectMappable {
  const Project({
    required this.id,
    required this.name,
    required this.repoPath,
    required this.createdAt,
    required this.updatedAt,
    this.kind = ProjectKind.gitRepository,
  });

  final String id;
  final String name;
  final String repoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProjectKind kind;

  bool get isGitRepository => kind == ProjectKind.gitRepository;

  bool get isFolder => kind == ProjectKind.folder;

  bool get supportsLinkedWorkspaces => isGitRepository;

  factory Project.fromJson(Map<String, Object?> json) =>
      ProjectMapper.fromMap(Map<String, dynamic>.from(json));
}
