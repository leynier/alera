enum WorkspaceTabKind {
  terminal('terminal'),
  editor('editor'),
  browser('browser');

  const WorkspaceTabKind(this.key);

  final String key;

  static WorkspaceTabKind fromJson(Object? value) {
    if (value == null) {
      return WorkspaceTabKind.terminal;
    }
    if (value is! String) {
      throw StateError('Workspace tab record has invalid kind');
    }
    for (final kind in WorkspaceTabKind.values) {
      if (kind.key == value) {
        return kind;
      }
    }
    throw StateError('Workspace tab record has unknown kind "$value"');
  }
}

const String workspaceTabManualTitlePayloadKey = 'manualTitle';

class WorkspaceTabRecord {
  WorkspaceTabRecord({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.kind = WorkspaceTabKind.terminal,
    Map<String, Object?> payload = const <String, Object?>{},
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  final String id;
  final String workspaceId;
  final WorkspaceTabKind kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> payload;

  bool get hasManualTitle => payload[workspaceTabManualTitlePayloadKey] == true;

  WorkspaceTabRecord copyWith({
    WorkspaceTabKind? kind,
    String? title,
    DateTime? updatedAt,
    Map<String, Object?>? payload,
  }) {
    return WorkspaceTabRecord(
      id: id,
      workspaceId: workspaceId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'workspaceId': workspaceId,
      'kind': kind.key,
      'title': title,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'payload': payload,
    };
  }

  factory WorkspaceTabRecord.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final workspaceId = json['workspaceId'];
    final title = json['title'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String || id.isEmpty) {
      throw StateError('Workspace tab record missing id');
    }
    if (workspaceId is! String || workspaceId.isEmpty) {
      throw StateError('Workspace tab record missing workspaceId');
    }
    if (title is! String || title.isEmpty) {
      throw StateError('Workspace tab record missing title');
    }
    if (createdAt is! String) {
      throw StateError('Workspace tab record missing createdAt');
    }
    if (updatedAt is! String) {
      throw StateError('Workspace tab record missing updatedAt');
    }
    return WorkspaceTabRecord(
      id: id,
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.fromJson(json['kind']),
      title: title,
      createdAt: DateTime.parse(createdAt).toUtc(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
      payload: _payloadFromJson(json['payload']),
    );
  }
}

Map<String, Object?> _payloadFromJson(Object? value) {
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is! Map) {
    throw StateError('Workspace tab record has invalid payload');
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
