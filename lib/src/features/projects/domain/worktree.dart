enum WorktreeStatus { active, removed }

WorktreeStatus _statusFromWire(String value) {
  for (final status in WorktreeStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  throw StateError('Unknown worktree status: $value');
}

class Worktree {
  const Worktree({
    required this.id,
    required this.projectId,
    required this.name,
    required this.branch,
    required this.path,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String projectId;
  final String name;
  final String branch;
  final String path;
  final DateTime createdAt;
  final WorktreeStatus status;

  Worktree copyWith({WorktreeStatus? status, String? path}) {
    return Worktree(
      id: id,
      projectId: projectId,
      name: name,
      branch: branch,
      path: path ?? this.path,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'projectId': projectId,
      'name': name,
      'branch': branch,
      'path': path,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'status': status.name,
    };
  }

  factory Worktree.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final projectId = json['projectId'];
    final name = json['name'];
    final branch = json['branch'];
    final path = json['path'];
    final createdAt = json['createdAt'];
    final status = json['status'];
    if (id is! String || id.isEmpty) {
      throw StateError('Worktree record missing id');
    }
    if (projectId is! String || projectId.isEmpty) {
      throw StateError('Worktree record missing projectId');
    }
    if (name is! String || name.isEmpty) {
      throw StateError('Worktree record missing name');
    }
    if (branch is! String || branch.isEmpty) {
      throw StateError('Worktree record missing branch');
    }
    if (path is! String || path.isEmpty) {
      throw StateError('Worktree record missing path');
    }
    if (createdAt is! String) {
      throw StateError('Worktree record missing createdAt');
    }
    if (status is! String) {
      throw StateError('Worktree record missing status');
    }
    return Worktree(
      id: id,
      projectId: projectId,
      name: name,
      branch: branch,
      path: path,
      createdAt: DateTime.parse(createdAt).toUtc(),
      status: _statusFromWire(status),
    );
  }
}
