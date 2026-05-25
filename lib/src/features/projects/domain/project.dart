enum ProjectKind { gitRepository, folder }

ProjectKind _projectKindFromWire(Object? value) {
  if (value == null) {
    // Existing databases were created when every project represented a Git
    // repository, so missing kind means the legacy Git behavior.
    return ProjectKind.gitRepository;
  }
  if (value is! String) {
    throw StateError('Project record has invalid kind');
  }
  for (final kind in ProjectKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }
  throw StateError('Unknown project kind: $value');
}

class Project {
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

  String get path => repoPath;

  bool get isGitRepository => kind == ProjectKind.gitRepository;

  bool get isFolder => kind == ProjectKind.folder;

  bool get supportsLinkedWorkspaces => isGitRepository;

  Project copyWith({
    String? name,
    String? repoPath,
    DateTime? updatedAt,
    ProjectKind? kind,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      repoPath: repoPath ?? this.repoPath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'repoPath': repoPath,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'kind': kind.name,
    };
  }

  factory Project.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final repoPath = json['repoPath'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    final kind = json['kind'];
    if (id is! String || id.isEmpty) {
      throw StateError('Project record missing id');
    }
    if (name is! String || name.isEmpty) {
      throw StateError('Project record missing name');
    }
    if (repoPath is! String || repoPath.isEmpty) {
      throw StateError('Project record missing repoPath');
    }
    if (createdAt is! String) {
      throw StateError('Project record missing createdAt');
    }
    if (updatedAt is! String) {
      throw StateError('Project record missing updatedAt');
    }
    return Project(
      id: id,
      name: name,
      repoPath: repoPath,
      createdAt: DateTime.parse(createdAt).toUtc(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
      kind: _projectKindFromWire(kind),
    );
  }
}
