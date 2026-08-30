part of 'mobile_codex_state.dart';

@immutable
class const MobileCodexCwdOption({
  required final String workspaceId,
  required final String name,
  required final String path,
}) {
  factory fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexCwdOption(
      workspaceId: _string(json['workspaceId']) ?? '',
      name: _string(json['name']) ?? _string(json['path']) ?? '',
      path: _string(json['path']) ?? '',
    );
  }

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
class const MobileCodexThreadSummary({
  required final String id,
  required final String title,
  final String? preview,
  final String? cwd,
  final String? workspaceId,
  final String? workspaceName,
  final String? boundTabId,
  final String? boundWorkspaceId,
  final bool canResume = true,
}) {
  factory fromJson(Object? value) {
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

  bool get isBound => boundTabId != null && boundTabId!.isNotEmpty;
}

@immutable
class const MobileCodexThreadPage({
  final List<MobileCodexThreadSummary> items =
      const <MobileCodexThreadSummary>[],
  final String? nextCursor,
  final List<MobileCodexCwdOption> cwdOptions = const <MobileCodexCwdOption>[],
}) {
  factory fromJson(Object? value) {
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

  MobileCodexThreadPage append(MobileCodexThreadPage next) =>
      MobileCodexThreadPage(
        items: <MobileCodexThreadSummary>[...items, ...next.items],
        nextCursor: next.nextCursor,
        cwdOptions: next.cwdOptions.isEmpty ? cwdOptions : next.cwdOptions,
      );
}

@immutable
class const MobileCodexThreadHistoryPage({
  required final MobileCodexState snapshot,
  final String? nextCursor,
}) {
  factory fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexThreadHistoryPage(
      snapshot: .fromSnapshot(json['snapshot']),
      nextCursor: _string(json['nextCursor']),
    );
  }
}

@immutable
class const MobileCodexThreadRecovery({
  required final String kind,
  required final String message,
}) {
  factory fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexThreadRecovery(
      kind: _string(json['kind']) ?? 'missingRollout',
      message:
          _string(json['message']) ??
          'The saved Codex context is no longer available.',
    );
  }
}
