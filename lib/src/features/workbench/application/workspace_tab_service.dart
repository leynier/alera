import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:uuid/uuid.dart';

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

  Future<WorkspaceTabRecord> createTerminalTab(String workspaceId) async {
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    final tabId = _uuid.v4();
    final tab = WorkspaceTabRecord(
      id: tabId,
      workspaceId: workspaceId,
      title: 'Terminal ${_nextOrdinal(existing)}',
      createdAt: _now(),
      updatedAt: _now(),
      payload: <String, Object?>{
        workspaceTabTerminalSessionIdPayloadKey: tabId,
      },
    );
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  Future<WorkspaceTabRecord> openOrCreateEditorTab({
    required String workspaceId,
    required String relativePath,
  }) async {
    final normalizedPath = _normalizeRelativePath(relativePath);
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind == WorkspaceTabKind.editor &&
          tab.payload[workspaceTabFilePathPayloadKey] == normalizedPath) {
        return tab;
      }
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.editor,
      title: _titleForPath(normalizedPath),
      createdAt: _now(),
      updatedAt: _now(),
      payload: <String, Object?>{
        workspaceTabFilePathPayloadKey: normalizedPath,
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
      throw StateError('Terminal title must not be empty');
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
      },
    );
    await _repository.upsertWorkspaceTab(next);
    return next;
  }

  Future<List<WorkspaceTabRecord>> updateEditorPathsAfterMove({
    required String workspaceId,
    required String oldRelativePath,
    required String newRelativePath,
  }) async {
    final oldPath = _normalizeRelativePath(oldRelativePath);
    final newPath = _normalizeRelativePath(newRelativePath);
    final tabs = await _repository.listWorkspaceTabs(workspaceId);
    final updated = <WorkspaceTabRecord>[];
    for (final tab in tabs) {
      if (tab.kind != WorkspaceTabKind.editor) {
        continue;
      }
      final filePath = tab.filePath;
      if (filePath == null) {
        continue;
      }
      final nextPath = _replacePathPrefix(
        path: filePath,
        oldPath: oldPath,
        newPath: newPath,
      );
      if (nextPath == null || nextPath == filePath) {
        continue;
      }
      final next = tab.copyWith(
        title: _titleForPath(nextPath),
        updatedAt: _now(),
        payload: <String, Object?>{
          ...tab.payload,
          workspaceTabFilePathPayloadKey: nextPath,
        },
      );
      await _repository.upsertWorkspaceTab(next);
      updated.add(next);
    }
    return updated;
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

  String? _replacePathPrefix({
    required String path,
    required String oldPath,
    required String newPath,
  }) {
    if (path == oldPath) {
      return newPath;
    }
    final prefix = '$oldPath/';
    if (!path.startsWith(prefix)) {
      return null;
    }
    return '$newPath/${path.substring(prefix.length)}';
  }
}
