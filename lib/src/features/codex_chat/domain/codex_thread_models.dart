part of 'codex_chat_models.dart';

@immutable
class CodexCwdOption {
  const CodexCwdOption({
    required this.workspaceId,
    required this.name,
    required this.path,
  });

  factory CodexCwdOption.fromJson(Object? value) {
    final json = _threadMap(value);
    return CodexCwdOption(
      workspaceId: json['workspaceId']?.toString() ?? '',
      name: json['name']?.toString() ?? json['path']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
    );
  }

  final String workspaceId;
  final String name;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is CodexCwdOption &&
      other.workspaceId == workspaceId &&
      other.name == name &&
      other.path == path;

  @override
  int get hashCode => Object.hash(workspaceId, name, path);
}

@immutable
class CodexThreadSummary {
  const CodexThreadSummary({
    required this.id,
    required this.title,
    this.preview,
    this.cwd,
    this.workspaceId,
    this.workspaceName,
    this.sourceKind,
    this.status,
    this.createdAt,
    this.updatedAt,
    this.recencyAt,
    this.isPinned = false,
    this.boundTabId,
    this.boundWorkspaceId,
    this.canResume = true,
  });

  factory CodexThreadSummary.fromJson(Object? value) {
    final json = _threadMap(value);
    final id = (json['threadId'] ?? json['id'])?.toString() ?? '';
    final title =
        _threadString(json, 'title') ??
        _threadString(json, 'name') ??
        _threadString(json, 'preview') ??
        'Untitled Codex Thread';
    return CodexThreadSummary(
      id: id,
      title: title,
      preview: _threadString(json, 'preview'),
      cwd: _threadString(json, 'cwd'),
      workspaceId: _threadString(json, 'workspaceId'),
      workspaceName: _threadString(json, 'workspaceName'),
      sourceKind: _threadString(json, 'sourceKind'),
      status: json['status'],
      createdAt: _threadDate(json['createdAt']),
      updatedAt: _threadDate(json['updatedAt']),
      recencyAt: _threadDate(json['recencyAt']),
      isPinned: json['isPinned'] == true,
      boundTabId: _threadString(json, 'boundTabId'),
      boundWorkspaceId: _threadString(json, 'boundWorkspaceId'),
      canResume: json['canResume'] != false,
    );
  }

  final String id;
  final String title;
  final String? preview;
  final String? cwd;
  final String? workspaceId;
  final String? workspaceName;
  final String? sourceKind;
  final Object? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? recencyAt;
  final bool isPinned;
  final String? boundTabId;
  final String? boundWorkspaceId;
  final bool canResume;

  bool get isBound => boundTabId != null && boundTabId!.isNotEmpty;
}

@immutable
class CodexThreadPage {
  const CodexThreadPage({
    this.items = const <CodexThreadSummary>[],
    this.nextCursor,
    this.backwardsCursor,
    this.cwdOptions = const <CodexCwdOption>[],
  });

  factory CodexThreadPage.fromJson(Object? value) {
    final json = _threadMap(value);
    final raw = json['items'] ?? json['threads'] ?? json['data'];
    return CodexThreadPage(
      items: <CodexThreadSummary>[
        if (raw is List)
          for (final item in raw) CodexThreadSummary.fromJson(item),
      ],
      nextCursor: _threadString(json, 'nextCursor'),
      backwardsCursor: _threadString(json, 'backwardsCursor'),
      cwdOptions: <CodexCwdOption>[
        if (json['cwdOptions'] is List)
          for (final item in json['cwdOptions'] as List)
            CodexCwdOption.fromJson(item),
      ],
    );
  }

  final List<CodexThreadSummary> items;
  final String? nextCursor;
  final String? backwardsCursor;
  final List<CodexCwdOption> cwdOptions;

  CodexThreadPage append(CodexThreadPage next) => CodexThreadPage(
    items: <CodexThreadSummary>[...items, ...next.items],
    nextCursor: next.nextCursor,
    backwardsCursor: next.backwardsCursor ?? backwardsCursor,
    cwdOptions: next.cwdOptions.isEmpty ? cwdOptions : next.cwdOptions,
  );
}

@immutable
class CodexThreadHistoryPage {
  const CodexThreadHistoryPage({
    required this.snapshot,
    this.items = const <Map<String, Object?>>[],
    this.nextCursor,
    this.backwardsCursor,
    this.cwd,
  });

  factory CodexThreadHistoryPage.fromJson(Object? value) {
    final json = _threadMap(value);
    final raw = json['items'] ?? json['data'];
    return CodexThreadHistoryPage(
      snapshot: CodexChatSnapshot.fromJson(json['snapshot']),
      items: <Map<String, Object?>>[
        if (raw is List)
          for (final item in raw)
            if (item is Map) Map<String, Object?>.from(item),
      ],
      nextCursor: _threadString(json, 'nextCursor'),
      backwardsCursor: _threadString(json, 'backwardsCursor'),
      cwd: _threadString(json, 'cwd'),
    );
  }

  final CodexChatSnapshot snapshot;
  final List<Map<String, Object?>> items;
  final String? nextCursor;
  final String? backwardsCursor;
  final String? cwd;
}

Map<String, Object?> _threadMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

String? _threadString(Map<String, Object?> json, String key) {
  final value = json[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

DateTime? _threadDate(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value * Duration.millisecondsPerSecond).round(),
      isUtc: true,
    );
  }
  return value is String ? DateTime.tryParse(value) : null;
}
