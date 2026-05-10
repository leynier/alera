class Project {
  const Project({
    required this.id,
    required this.name,
    required this.repoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String repoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project copyWith({String? name, String? repoPath, DateTime? updatedAt}) {
    return Project(
      id: id,
      name: name ?? this.name,
      repoPath: repoPath ?? this.repoPath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'repoPath': repoPath,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Project.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final repoPath = json['repoPath'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
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
    );
  }
}
