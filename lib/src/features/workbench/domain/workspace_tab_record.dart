import 'package:dart_mappable/dart_mappable.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';

part 'workspace_tab_record.mapper.dart';

@MappableEnum()
enum WorkspaceTabKind {
  terminal('terminal'),
  codex('codex'),
  editor('editor'),
  markdownViewer('markdownViewer'),
  pdf('pdf'),
  gitDiff('gitDiff'),
  browser('browser'),
  mobileEmulator('mobileEmulator');

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
const String workspaceTabTerminalSessionIdPayloadKey = 'terminalSessionId';
const String workspaceTabCodexThreadIdPayloadKey = 'codexThreadId';
const String workspaceTabCodexSnapshotPayloadKey = 'codexSnapshot';
const String workspaceTabCodexActiveTurnIdPayloadKey = 'codexActiveTurnId';
const String workspaceTabInitialCommandPayloadKey = 'initialCommand';
const String workspaceTabInitialCommandOncePayloadKey = 'initialCommandOnce';
const String workspaceTabSpawnOnCreatePayloadKey = 'spawnOnCreate';
const String workspaceTabAutoCloseOnSuccessPayloadKey = 'autoCloseOnSuccess';
const String workspaceTabTerminalPulsePayloadKey = 'terminalPulse';
const String workspaceTabFilePathPayloadKey = 'filePath';
const String workspaceTabFileRolePayloadKey = 'fileRole';
const String workspaceTabFileRoleMermanPreview = 'mermanPreview';
const String workspaceTabBrowserProfileIdPayloadKey = 'browserProfileId';
const String workspaceTabBrowserUrlPayloadKey = 'browserUrl';
const String workspaceTabBrowserRuntimeTitlePayloadKey = 'browserRuntimeTitle';
const String workspaceTabGitDiffScopePayloadKey = 'gitDiffScope';
const String workspaceTabGitDiffAreaPayloadKey = 'gitDiffArea';
const String workspaceTabGitDiffRootPayloadKey = 'gitDiffRoot';
const String workspaceTabGitDiffSourcePayloadKey = 'gitDiffSource';
const String workspaceTabGitDiffCommitOidPayloadKey = 'gitDiffCommitOid';
const String workspaceTabGitDiffParentOidPayloadKey = 'gitDiffParentOid';
const String workspaceTabGitDiffCompareRefPayloadKey = 'gitDiffCompareRef';
const String workspaceTabGitDiffCommitSubjectPayloadKey =
    'gitDiffCommitSubject';
const String workspaceTabGitDiffCommitMessagePayloadKey =
    'gitDiffCommitMessage';
const String workspaceTabGitDiffOldPathPayloadKey = 'gitDiffOldPath';
const String workspaceTabMobileEmulatorPayloadKey = 'mobileEmulator';

enum MobileEmulatorPlatform {
  android('android', 'Android'),
  ios('ios', 'iOS');

  const MobileEmulatorPlatform(this.key, this.label);

  final String key;
  final String label;

  static MobileEmulatorPlatform? fromJson(Object? value) {
    for (final platform in values) {
      if (platform.key == value) {
        return platform;
      }
    }
    return null;
  }
}

class WorkspaceMobileEmulatorPayload {
  const WorkspaceMobileEmulatorPayload({
    required this.platform,
    required this.deviceId,
  });

  static const int schemaVersion = 1;

  final MobileEmulatorPlatform platform;
  final String deviceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'platform': platform.key,
    'deviceId': deviceId,
  };

  static WorkspaceMobileEmulatorPayload? fromJson(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != schemaVersion ||
        value['deviceId'] is! String) {
      return null;
    }
    final platform = MobileEmulatorPlatform.fromJson(value['platform']);
    final deviceId = (value['deviceId'] as String).trim();
    if (platform == null || deviceId.isEmpty) {
      return null;
    }
    return WorkspaceMobileEmulatorPayload(
      platform: platform,
      deviceId: deviceId,
    );
  }
}

enum WorkspaceGitDiffSource {
  workingTree('workingTree'),
  commit('commit');

  const WorkspaceGitDiffSource(this.key);

  final String key;

  static WorkspaceGitDiffSource fromJson(Object? value) {
    if (value is! String) {
      return WorkspaceGitDiffSource.workingTree;
    }
    for (final source in WorkspaceGitDiffSource.values) {
      if (source.key == value) {
        return source;
      }
    }
    return WorkspaceGitDiffSource.workingTree;
  }
}

enum WorkspaceGitDiffScope {
  file('file'),
  all('all'),
  fileAll('fileAll');

  const WorkspaceGitDiffScope(this.key);

  final String key;

  static WorkspaceGitDiffScope? fromJson(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final scope in WorkspaceGitDiffScope.values) {
      if (scope.key == value) {
        return scope;
      }
    }
    return null;
  }
}

bool isWorkspaceMarkdownFilePath(String path) =>
    path.toLowerCase().endsWith('.md');

@MappableClass()
class WorkspaceTabRecord with WorkspaceTabRecordMappable {
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

  String get terminalSessionId {
    final value = payload[workspaceTabTerminalSessionIdPayloadKey];
    return value is String && value.trim().isNotEmpty ? value : id;
  }

  String? get codexThreadId =>
      _nonEmptyPayloadString(workspaceTabCodexThreadIdPayloadKey);

  Map<String, Object?> get codexSnapshot {
    final value = payload[workspaceTabCodexSnapshotPayloadKey];
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return const <String, Object?>{};
  }

  String? get codexActiveTurnId =>
      _nonEmptyPayloadString(workspaceTabCodexActiveTurnIdPayloadKey);

  /// Command written into the terminal after the shell starts, e.g. an agent
  /// CLI launched by an orchestration coordinator. Runs once for each newly
  /// created PTY, including a transparent remint after host recovery.
  String? get initialCommand =>
      _nonEmptyPayloadString(workspaceTabInitialCommandPayloadKey);

  /// Whether [initialCommand] is spent after the first delivery. The host drops
  /// it from the record once it is on its way, so a later PTY starts a clean
  /// shell. Agent tabs leave this off because they want the remint.
  bool get initialCommandOnce =>
      payload[workspaceTabInitialCommandOncePayloadKey] == true;

  /// Whether the terminal session should start as soon as the tab record
  /// appears, without waiting for the tab to become visible.
  bool get spawnOnCreate =>
      payload[workspaceTabSpawnOnCreatePayloadKey] == true;

  /// Whether a terminal whose one-shot command exits successfully should be
  /// removed automatically. Failed commands stay visible for inspection.
  bool get autoCloseOnSuccess =>
      payload[workspaceTabAutoCloseOnSuccessPayloadKey] == true;

  TerminalPulseConfiguration get terminalPulse =>
      TerminalPulseConfiguration.fromJson(
        payload[workspaceTabTerminalPulsePayloadKey],
      );

  String? get filePath {
    final value = payload[workspaceTabFilePathPayloadKey];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  bool get isMermanPreview {
    return payload[workspaceTabFileRolePayloadKey] ==
        workspaceTabFileRoleMermanPreview;
  }

  String get browserProfileId =>
      _nonEmptyPayloadString(workspaceTabBrowserProfileIdPayloadKey) ??
      'default';

  String? get browserUrl =>
      _nonEmptyPayloadString(workspaceTabBrowserUrlPayloadKey);

  String? get browserRuntimeTitle =>
      _nonEmptyPayloadString(workspaceTabBrowserRuntimeTitlePayloadKey);

  WorkspaceMobileEmulatorPayload? get mobileEmulator =>
      WorkspaceMobileEmulatorPayload.fromJson(
        payload[workspaceTabMobileEmulatorPayloadKey],
      );

  WorkspaceGitDiffScope? get gitDiffScope => WorkspaceGitDiffScope.fromJson(
    payload[workspaceTabGitDiffScopePayloadKey],
  );

  WorkspaceGitDiffSource get gitDiffSource => WorkspaceGitDiffSource.fromJson(
    payload[workspaceTabGitDiffSourcePayloadKey],
  );

  String? get gitDiffRoot {
    final value = payload[workspaceTabGitDiffRootPayloadKey];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  GitChangeArea? get gitDiffArea {
    final value = payload[workspaceTabGitDiffAreaPayloadKey];
    if (value is! String) {
      return null;
    }
    for (final area in GitChangeArea.values) {
      if (area.key == value) {
        return area;
      }
    }
    return null;
  }

  String? get gitDiffCommitOid =>
      _nonEmptyPayloadString(workspaceTabGitDiffCommitOidPayloadKey);

  String? get gitDiffParentOid =>
      _nonEmptyPayloadString(workspaceTabGitDiffParentOidPayloadKey);

  String? get gitDiffCompareRef =>
      _nonEmptyPayloadString(workspaceTabGitDiffCompareRefPayloadKey);

  String? get gitDiffCommitSubject =>
      _nonEmptyPayloadString(workspaceTabGitDiffCommitSubjectPayloadKey);

  String? get gitDiffCommitMessage =>
      _nonEmptyPayloadString(workspaceTabGitDiffCommitMessagePayloadKey);

  String? get gitDiffOldPath =>
      _nonEmptyPayloadString(workspaceTabGitDiffOldPathPayloadKey);

  String? _nonEmptyPayloadString(String key) {
    final value = payload[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  factory WorkspaceTabRecord.fromJson(Map<String, Object?> json) =>
      WorkspaceTabRecordMapper.fromMap(Map<String, dynamic>.from(json));
}

final class TerminalPulseConfiguration {
  const TerminalPulseConfiguration({
    this.command = 'r',
    this.appendEnter = true,
    this.delayMilliseconds = 2000,
  });

  factory TerminalPulseConfiguration.fromJson(Object? value) {
    if (value is! Map) {
      return const TerminalPulseConfiguration();
    }
    final command = value['command'];
    final delayMilliseconds = value['delayMs'];
    return TerminalPulseConfiguration(
      command: command is String && command.isNotEmpty ? command : 'r',
      appendEnter: value['appendEnter'] != false,
      delayMilliseconds: delayMilliseconds is int && delayMilliseconds > 0
          ? delayMilliseconds
          : 2000,
    );
  }

  final String command;
  final bool appendEnter;
  final int delayMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'appendEnter': appendEnter,
    'delayMs': delayMilliseconds,
  };

  TerminalPulseConfiguration copyWith({
    String? command,
    bool? appendEnter,
    int? delayMilliseconds,
  }) => TerminalPulseConfiguration(
    command: command ?? this.command,
    appendEnter: appendEnter ?? this.appendEnter,
    delayMilliseconds: delayMilliseconds ?? this.delayMilliseconds,
  );

  @override
  bool operator ==(Object other) =>
      other is TerminalPulseConfiguration &&
      other.command == command &&
      other.appendEnter == appendEnter &&
      other.delayMilliseconds == delayMilliseconds;

  @override
  int get hashCode => Object.hash(command, appendEnter, delayMilliseconds);
}
