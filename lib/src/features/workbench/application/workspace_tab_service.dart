import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:uuid/uuid.dart';

part 'workspace_tab_path_moves.dart';
part 'workspace_tab_file_opening.dart';
part 'workspace_tab_git_opening.dart';

class WorkspaceTabService {
  factory WorkspaceTabService({
    required WorkbenchRepository repository,
    Uuid? uuid,
    DateTime Function()? now,
  }) {
    return WorkspaceTabService._(
      repository,
      uuid ?? const Uuid(),
      now ?? _defaultNow,
    );
  }

  WorkspaceTabService._(this._repository, this._uuid, this._now);

  final WorkbenchRepository _repository;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  Future<List<WorkspaceTabRecord>> listTabs(String workspaceId) {
    return _repository.listWorkspaceTabs(workspaceId);
  }

  Future<WorkspaceTabRecord> ensureInitialTerminalTab(
    String workspaceId,
  ) async {
    final tabs = await _repository.listWorkspaceTabs(workspaceId);
    if (tabs.isNotEmpty) {
      return tabs.first;
    }
    return createTerminalTab(workspaceId);
  }

  /// Creates a terminal tab.
  ///
  /// A [title] also pins the tab against runtime OSC retitling, because a
  /// caller that named the tab meant that name. [initialCommand] is written
  /// into the shell once it starts; with [spawnOnCreate] the host starts the
  /// PTY immediately instead of waiting for the tab to become visible, and with
  /// [initialCommandOnce] the command is dropped from the record after the
  /// first delivery so a later PTY starts a clean shell.
  Future<WorkspaceTabRecord> createTerminalTab(
    String workspaceId, {
    String? title,
    String? initialCommand,
    bool spawnOnCreate = false,
    bool initialCommandOnce = false,
    bool autoCloseOnSuccess = false,
  }) async {
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    final tabId = _uuid.v4();
    final trimmedTitle = title?.trim();
    final trimmedCommand = initialCommand?.trim();
    final tab = WorkspaceTabRecord(
      id: tabId,
      workspaceId: workspaceId,
      title: trimmedTitle == null || trimmedTitle.isEmpty
          ? 'Terminal ${_nextOrdinal(existing)}'
          : trimmedTitle,
      createdAt: _now(),
      updatedAt: _now(),
      payload: <String, Object?>{
        workspaceTabTerminalSessionIdPayloadKey: tabId,
        if (trimmedTitle != null && trimmedTitle.isNotEmpty)
          workspaceTabManualTitlePayloadKey: true,
        if (trimmedCommand != null && trimmedCommand.isNotEmpty) ...{
          workspaceTabInitialCommandPayloadKey: trimmedCommand,
          if (initialCommandOnce)
            workspaceTabInitialCommandOncePayloadKey: true,
        },
        if (spawnOnCreate) workspaceTabSpawnOnCreatePayloadKey: true,
        if (autoCloseOnSuccess) workspaceTabAutoCloseOnSuccessPayloadKey: true,
      },
    );
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  Future<WorkspaceTabRecord> createCodexTab(String workspaceId) async {
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    final now = _now();
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.codex,
      title: 'Codex Chat',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{},
    );
    // The next ordinal is deliberately not used because Codex Chat has one
    // stable product label regardless of its conversation metadata.
    if (existing.any((candidate) => candidate.id == tab.id)) {
      throw StateError('Could not allocate a unique Codex tab id.');
    }
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  Future<WorkspaceTabRecord> openOrCreateMermanPreviewTab({
    required String workspaceId,
    required String relativePath,
  }) async {
    final normalizedPath = _normalizeRelativePath(relativePath);
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind == WorkspaceTabKind.editor &&
          tab.isMermanPreview &&
          tab.payload[workspaceTabFilePathPayloadKey] == normalizedPath) {
        return tab;
      }
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.editor,
      title: _previewTitleForPath(normalizedPath),
      createdAt: _now(),
      updatedAt: _now(),
      payload: <String, Object?>{
        workspaceTabFilePathPayloadKey: normalizedPath,
        workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
      },
    );
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  Future<void> closeTab(String tabId) {
    return _repository.removeWorkspaceTab(tabId);
  }

  Future<WorkspaceTabRecord> renameTab({
    required String tabId,
    required String title,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw StateError('Tab title must not be empty');
    }
    final tab = await _repository.findWorkspaceTabById(tabId);
    if (tab == null) {
      throw StateError('Workspace tab not found: $tabId');
    }
    final next = tab.copyWith(
      title: trimmedTitle,
      updatedAt: _now(),
      payload: <String, Object?>{
        ...tab.payload,
        workspaceTabManualTitlePayloadKey: true,
        'agentTitleSource': 'manual',
      },
    );
    return _repository.upsertWorkspaceTab(next, manualRename: true);
  }

  int _nextOrdinal(List<WorkspaceTabRecord> tabs) {
    final used = <int>{};
    for (final tab in tabs) {
      final match = RegExp(r'^Terminal (\d+)$').firstMatch(tab.title);
      if (match == null) {
        continue;
      }
      used.add(int.parse(match.group(1)!));
    }
    var ordinal = 1;
    while (used.contains(ordinal)) {
      ordinal += 1;
    }
    return ordinal;
  }

  String _normalizeRelativePath(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.trim().isNotEmpty && part != '.')
        .join('/');
    if (normalized.isEmpty || normalized.split('/').contains('..')) {
      throw StateError('File path must stay inside the workspace');
    }
    return normalized;
  }

  String _titleForPath(String path) {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _previewTitleForPath(String path) {
    return '${_titleForPath(path)} preview';
  }

  WorkspaceTabKind _fileBackedKindForPath(String path) {
    if (isWorkspaceMarkdownFilePath(path)) {
      return WorkspaceTabKind.markdownViewer;
    }
    if (isWorkspacePdfFilePath(path)) {
      return WorkspaceTabKind.pdf;
    }
    return WorkspaceTabKind.editor;
  }
}
