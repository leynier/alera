part of 'mobile_codex_state.dart';

@immutable
class MobileCodexCwdOption {
  const MobileCodexCwdOption({
    required this.workspaceId,
    required this.name,
    required this.path,
  });

  factory MobileCodexCwdOption.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexCwdOption(
      workspaceId: _string(json['workspaceId']) ?? '',
      name: _string(json['name']) ?? _string(json['path']) ?? '',
      path: _string(json['path']) ?? '',
    );
  }

  final String workspaceId;
  final String name;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is MobileCodexCwdOption &&
      other.workspaceId == workspaceId &&
      other.name == name &&
      other.path == path;

  @override
  int get hashCode => Object.hash(workspaceId, name, path);
}

@immutable
class MobileCodexThreadSummary {
  const MobileCodexThreadSummary({
    required this.id,
    required this.title,
    this.preview,
    this.cwd,
    this.workspaceId,
    this.workspaceName,
    this.boundTabId,
    this.boundWorkspaceId,
    this.canResume = true,
  });

  factory MobileCodexThreadSummary.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexThreadSummary(
      id: _string(json['threadId'] ?? json['id']) ?? '',
      title:
          _string(json['title']) ??
          _string(json['name']) ??
          _string(json['preview']) ??
          'Untitled Codex Thread',
      preview: _string(json['preview']),
      cwd: _string(json['cwd']),
      workspaceId: _string(json['workspaceId']),
      workspaceName: _string(json['workspaceName']),
      boundTabId: _string(json['boundTabId']),
      boundWorkspaceId: _string(json['boundWorkspaceId']),
      canResume: json['canResume'] != false,
    );
  }

  final String id;
  final String title;
  final String? preview;
  final String? cwd;
  final String? workspaceId;
  final String? workspaceName;
  final String? boundTabId;
  final String? boundWorkspaceId;
  final bool canResume;

  bool get isBound => boundTabId != null && boundTabId!.isNotEmpty;
}

@immutable
class MobileCodexThreadPage {
  const MobileCodexThreadPage({
    this.items = const <MobileCodexThreadSummary>[],
    this.nextCursor,
    this.cwdOptions = const <MobileCodexCwdOption>[],
  });

  factory MobileCodexThreadPage.fromJson(Object? value) {
    final json = _map(value);
    final raw = json['items'] ?? json['threads'] ?? json['data'];
    return MobileCodexThreadPage(
      items: <MobileCodexThreadSummary>[
        if (raw is List)
          for (final item in raw) MobileCodexThreadSummary.fromJson(item),
      ],
      nextCursor: _string(json['nextCursor']),
      cwdOptions: <MobileCodexCwdOption>[
        if (json['cwdOptions'] is List)
          for (final item in json['cwdOptions'] as List)
            MobileCodexCwdOption.fromJson(item),
      ],
    );
  }

  final List<MobileCodexThreadSummary> items;
  final String? nextCursor;
  final List<MobileCodexCwdOption> cwdOptions;

  MobileCodexThreadPage append(MobileCodexThreadPage next) =>
      MobileCodexThreadPage(
        items: <MobileCodexThreadSummary>[...items, ...next.items],
        nextCursor: next.nextCursor,
        cwdOptions: next.cwdOptions.isEmpty ? cwdOptions : next.cwdOptions,
      );
}

@immutable
class MobileCodexThreadHistoryPage {
  const MobileCodexThreadHistoryPage({required this.snapshot, this.nextCursor});

  factory MobileCodexThreadHistoryPage.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexThreadHistoryPage(
      snapshot: MobileCodexState.fromSnapshot(json['snapshot']),
      nextCursor: _string(json['nextCursor']),
    );
  }

  final MobileCodexState snapshot;
  final String? nextCursor;
}

@immutable
class MobileCodexThreadRecovery {
  const MobileCodexThreadRecovery({required this.kind, required this.message});

  factory MobileCodexThreadRecovery.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexThreadRecovery(
      kind: _string(json['kind']) ?? 'missingRollout',
      message:
          _string(json['message']) ??
          'The saved Codex context is no longer available.',
    );
  }

  final String kind;
  final String message;
}
