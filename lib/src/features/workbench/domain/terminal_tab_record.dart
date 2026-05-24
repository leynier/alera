class TerminalTabRecord {
  const TerminalTabRecord({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  TerminalTabRecord copyWith({String? title, DateTime? updatedAt}) {
    return TerminalTabRecord(
      id: id,
      workspaceId: workspaceId,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'workspaceId': workspaceId,
      'title': title,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory TerminalTabRecord.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final workspaceId = json['workspaceId'];
    final title = json['title'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String || id.isEmpty) {
      throw StateError('Terminal tab record missing id');
    }
    if (workspaceId is! String || workspaceId.isEmpty) {
      throw StateError('Terminal tab record missing workspaceId');
    }
    if (title is! String || title.isEmpty) {
      throw StateError('Terminal tab record missing title');
    }
    if (createdAt is! String) {
      throw StateError('Terminal tab record missing createdAt');
    }
    if (updatedAt is! String) {
      throw StateError('Terminal tab record missing updatedAt');
    }
    return TerminalTabRecord(
      id: id,
      workspaceId: workspaceId,
      title: title,
      createdAt: DateTime.parse(createdAt).toUtc(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
    );
  }
}
