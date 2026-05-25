enum WorkspaceKind { main, linked }

enum WorkspaceStatus { active, removed }

const Object _unset = Object();

WorkspaceKind _workspaceKindFromWire(String value) {
  for (final kind in WorkspaceKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }
  throw StateError('Unknown workspace kind: $value');
}

WorkspaceStatus _workspaceStatusFromWire(String value) {
  for (final status in WorkspaceStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  throw StateError('Unknown workspace status: $value');
}

class Workspace {
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

  bool get isMain => kind == WorkspaceKind.main;

  bool get isActive => status == WorkspaceStatus.active;

  Workspace copyWith({
    String? name,
    Object? branch = _unset,
    String? path,
    DateTime? updatedAt,
    WorkspaceKind? kind,
    WorkspaceStatus? status,
    String? sourceBranch,
    bool clearSourceBranch = false,
  }) {
    return Workspace(
      id: id,
      projectId: projectId,
      name: name ?? this.name,
      branch: identical(branch, _unset) ? this.branch : branch as String?,
      path: path ?? this.path,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      sourceBranch: clearSourceBranch
          ? null
          : (sourceBranch ?? this.sourceBranch),
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
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'kind': kind.name,
      'status': status.name,
      'sourceBranch': sourceBranch,
    };
  }

  factory Workspace.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final projectId = json['projectId'];
    final name = json['name'];
    final branch = json['branch'];
    final path = json['path'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    final kind = json['kind'];
    final status = json['status'];
    if (id is! String || id.isEmpty) {
      throw StateError('Workspace record missing id');
    }
    if (projectId is! String || projectId.isEmpty) {
      throw StateError('Workspace record missing projectId');
    }
    if (name is! String || name.isEmpty) {
      throw StateError('Workspace record missing name');
    }
    if (branch != null && branch is! String) {
      throw StateError('Workspace record has invalid branch');
    }
    if (path is! String || path.isEmpty) {
      throw StateError('Workspace record missing path');
    }
    if (createdAt is! String) {
      throw StateError('Workspace record missing createdAt');
    }
    if (updatedAt is! String) {
      throw StateError('Workspace record missing updatedAt');
    }
    if (kind is! String) {
      throw StateError('Workspace record missing kind');
    }
    if (status is! String) {
      throw StateError('Workspace record missing status');
    }
    final sourceBranch = json['sourceBranch'];
    return Workspace(
      id: id,
      projectId: projectId,
      name: name,
      branch: branch is String && branch.isNotEmpty ? branch : null,
      path: path,
      createdAt: DateTime.parse(createdAt).toUtc(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
      kind: _workspaceKindFromWire(kind),
      status: _workspaceStatusFromWire(status),
      sourceBranch: sourceBranch is String && sourceBranch.isNotEmpty
          ? sourceBranch
          : null,
    );
  }
}
