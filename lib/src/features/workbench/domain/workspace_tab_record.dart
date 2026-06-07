import 'package:dart_mappable/dart_mappable.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';

part 'workspace_tab_record.mapper.dart';

@MappableEnum()
enum WorkspaceTabKind {
  terminal('terminal'),
  editor('editor'),
  markdownViewer('markdownViewer'),
  pdf('pdf'),
  gitDiff('gitDiff'),
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
const String workspaceTabTerminalSessionIdPayloadKey = 'terminalSessionId';
const String workspaceTabFilePathPayloadKey = 'filePath';
const String workspaceTabFileRolePayloadKey = 'fileRole';
const String workspaceTabFileRoleMermanPreview = 'mermanPreview';
const String workspaceTabGitDiffScopePayloadKey = 'gitDiffScope';
const String workspaceTabGitDiffAreaPayloadKey = 'gitDiffArea';

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

  String? get filePath {
    final value = payload[workspaceTabFilePathPayloadKey];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  bool get isMermanPreview {
    return payload[workspaceTabFileRolePayloadKey] ==
        workspaceTabFileRoleMermanPreview;
  }

  WorkspaceGitDiffScope? get gitDiffScope => WorkspaceGitDiffScope.fromJson(
    payload[workspaceTabGitDiffScopePayloadKey],
  );

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

  factory WorkspaceTabRecord.fromJson(Map<String, Object?> json) =>
      WorkspaceTabRecordMapper.fromMap(Map<String, dynamic>.from(json));
}
