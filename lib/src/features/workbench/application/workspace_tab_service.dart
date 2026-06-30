import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:uuid/uuid.dart';

class WorkspaceFileTabPathMoveResult {
  const WorkspaceFileTabPathMoveResult({
    required this.updatedTabs,
    required this.closedTabIds,
  });

  final List<WorkspaceTabRecord> updatedTabs;
  final List<String> closedTabIds;

  List<String> get removedTabIds => closedTabIds;

  bool get isEmpty => updatedTabs.isEmpty && closedTabIds.isEmpty;
}

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
    return _openOrCreateFileTab(
      workspaceId: workspaceId,
      relativePath: relativePath,
      kind: WorkspaceTabKind.editor,
    );
  }

  Future<WorkspaceTabRecord> openOrCreatePdfTab({
    required String workspaceId,
    required String relativePath,
  }) async {
    return _openOrCreateFileTab(
      workspaceId: workspaceId,
      relativePath: relativePath,
      kind: WorkspaceTabKind.pdf,
    );
  }

  Future<WorkspaceTabRecord> openOrCreateMarkdownViewerTab({
    required String workspaceId,
    required String relativePath,
  }) async {
    final normalizedPath = _normalizeRelativePath(relativePath);
    if (!isWorkspaceMarkdownFilePath(normalizedPath)) {
      throw StateError('Markdown viewer tabs require a .md file');
    }
    return _openOrCreateFileTab(
      workspaceId: workspaceId,
      relativePath: normalizedPath,
      kind: WorkspaceTabKind.markdownViewer,
    );
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

  Future<WorkspaceTabRecord> openOrCreateGitDiffTab({
    required String workspaceId,
    String? relativePath,
    GitChangeArea? area,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
  }) async {
    final normalizedPath = relativePath == null
        ? null
        : _normalizeRelativePath(relativePath);
    final normalizedRoot = normalizeSourceControlRootRelativePath(gitDiffRoot);
    if (scope == WorkspaceGitDiffScope.file && area == null) {
      throw StateError('Git diff file tabs require an area.');
    }
    if (scope != WorkspaceGitDiffScope.all && normalizedPath == null) {
      throw StateError('Git diff file tabs require a file path.');
    }
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind != WorkspaceTabKind.gitDiff) {
        continue;
      }
      if (tab.gitDiffScope == scope &&
          tab.filePath == normalizedPath &&
          tab.gitDiffRoot == normalizedRoot &&
          tab.gitDiffArea == area) {
        return tab;
      }
    }
    final payload = <String, Object?>{
      workspaceTabGitDiffScopePayloadKey: scope.key,
      if (area != null) workspaceTabGitDiffAreaPayloadKey: area.key,
      ...switch (normalizedRoot) {
        null => const <String, Object?>{},
        final root => <String, Object?>{
          workspaceTabGitDiffRootPayloadKey: root,
        },
      },
    };
    if (normalizedPath != null) {
      payload[workspaceTabFilePathPayloadKey] = normalizedPath;
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.gitDiff,
      title: _titleForGitDiff(
        scope: scope,
        path: normalizedPath,
        area: area,
        root: normalizedRoot,
      ),
      createdAt: _now(),
      updatedAt: _now(),
      payload: payload,
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

  Future<WorkspaceFileTabPathMoveResult> updateFileTabPathsAfterMove({
    required String workspaceId,
    required String oldRelativePath,
    required String newRelativePath,
  }) async {
    final oldPath = _normalizeRelativePath(oldRelativePath);
    final newPath = _normalizeRelativePath(newRelativePath);
    final tabs = await _repository.listWorkspaceTabs(workspaceId);
    final updatedById = <String, WorkspaceTabRecord>{};
    final closed = <String>[];
    final fileBackedPaths = <String>{};
    void trackUpdated(WorkspaceTabRecord tab) {
      updatedById[tab.id] = tab;
    }

    for (final tab in tabs) {
      if (tab.kind != WorkspaceTabKind.gitDiff || tab.gitDiffRoot == null) {
        continue;
      }
      final root = tab.gitDiffRoot!;
      final nextRoot = _replacePathPrefix(
        path: root,
        oldPath: oldPath,
        newPath: newPath,
      );
      if (nextRoot == null || nextRoot == root) {
        continue;
      }
      final next = tab.copyWith(
        title: _titleForGitDiff(
          scope: tab.gitDiffScope ?? WorkspaceGitDiffScope.file,
          path: tab.filePath,
          area: tab.gitDiffArea,
          root: nextRoot,
        ),
        updatedAt: _now(),
        payload: <String, Object?>{
          ...tab.payload,
          workspaceTabGitDiffRootPayloadKey: nextRoot,
        },
      );
      await _repository.upsertWorkspaceTab(next);
      trackUpdated(next);
    }
    for (final tab in tabs) {
      if (_isRetargetableFileBackedTab(tab) && !tab.isMermanPreview) {
        final filePath = tab.filePath;
        if (filePath != null) {
          fileBackedPaths.add(
            _replacePathPrefix(
                  path: filePath,
                  oldPath: oldPath,
                  newPath: newPath,
                ) ??
                filePath,
          );
        }
      }
    }
    for (final originalTab in tabs) {
      final rootWasRetargeted = updatedById.containsKey(originalTab.id);
      final tab = updatedById[originalTab.id] ?? originalTab;
      if (!_isFileTabKind(tab.kind)) {
        continue;
      }
      if (tab.kind == WorkspaceTabKind.gitDiff &&
          tab.gitDiffArea == GitChangeArea.staged &&
          !rootWasRetargeted) {
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
      final nextKind = _fileTabKindAfterPathMove(tab: tab, nextPath: nextPath);
      if (tab.isMermanPreview && !isWorkspaceMermanFilePath(nextPath)) {
        if (fileBackedPaths.contains(nextPath)) {
          await _repository.removeWorkspaceTab(tab.id);
          closed.add(tab.id);
          updatedById.remove(tab.id);
          continue;
        }
        final nextPayload = <String, Object?>{
          ...tab.payload,
          workspaceTabFilePathPayloadKey: nextPath,
        }..remove(workspaceTabFileRolePayloadKey);
        final next = tab.copyWith(
          kind: _fileBackedKindForPath(nextPath),
          title: _titleForPath(nextPath),
          updatedAt: _now(),
          payload: nextPayload,
        );
        await _repository.upsertWorkspaceTab(next);
        trackUpdated(next);
        fileBackedPaths.add(nextPath);
        continue;
      }
      if (nextKind == null) {
        await _repository.removeWorkspaceTab(tab.id);
        closed.add(tab.id);
        updatedById.remove(tab.id);
        continue;
      }
      final next = tab.copyWith(
        kind: nextKind,
        title: tab.isMermanPreview
            ? _previewTitleForPath(nextPath)
            : tab.kind == WorkspaceTabKind.gitDiff
            ? _titleForGitDiff(
                scope: tab.gitDiffScope ?? WorkspaceGitDiffScope.file,
                path: nextPath,
                area: tab.gitDiffArea,
                root: tab.gitDiffRoot,
              )
            : _titleForPath(nextPath),
        updatedAt: _now(),
        payload: <String, Object?>{
          ...tab.payload,
          workspaceTabFilePathPayloadKey: nextPath,
        },
      );
      await _repository.upsertWorkspaceTab(next);
      trackUpdated(next);
    }
    return WorkspaceFileTabPathMoveResult(
      updatedTabs: List<WorkspaceTabRecord>.unmodifiable(updatedById.values),
      closedTabIds: List<String>.unmodifiable(closed),
    );
  }

  Future<WorkspaceFileTabPathMoveResult> updateEditorPathsAfterMove({
    required String workspaceId,
    required String oldRelativePath,
    required String newRelativePath,
  }) {
    return updateFileTabPathsAfterMove(
      workspaceId: workspaceId,
      oldRelativePath: oldRelativePath,
      newRelativePath: newRelativePath,
    );
  }

  Future<WorkspaceTabRecord> _openOrCreateFileTab({
    required String workspaceId,
    required String relativePath,
    required WorkspaceTabKind kind,
  }) async {
    final normalizedPath = _normalizeRelativePath(relativePath);
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.isMermanPreview ||
          tab.payload[workspaceTabFilePathPayloadKey] != normalizedPath) {
        continue;
      }
      if (tab.kind == kind) {
        return tab;
      }
      if (!_canRetargetFileBackedTab(from: tab.kind, to: kind)) {
        continue;
      }
      final next = tab.copyWith(kind: kind, updatedAt: _now());
      await _repository.upsertWorkspaceTab(next);
      return next;
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: kind,
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

  bool _isFileTabKind(WorkspaceTabKind kind) {
    return switch (kind) {
      WorkspaceTabKind.editor ||
      WorkspaceTabKind.markdownViewer ||
      WorkspaceTabKind.pdf ||
      WorkspaceTabKind.gitDiff => true,
      WorkspaceTabKind.terminal || WorkspaceTabKind.browser => false,
    };
  }

  bool _canRetargetFileBackedTab({
    required WorkspaceTabKind from,
    required WorkspaceTabKind to,
  }) {
    return switch ((from, to)) {
      (WorkspaceTabKind.editor, WorkspaceTabKind.pdf) ||
      (WorkspaceTabKind.pdf, WorkspaceTabKind.editor) => true,
      _ => false,
    };
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

  bool _isRetargetableFileBackedTab(WorkspaceTabRecord tab) {
    return tab.kind == WorkspaceTabKind.editor ||
        tab.kind == WorkspaceTabKind.pdf ||
        tab.kind == WorkspaceTabKind.markdownViewer;
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

  WorkspaceTabKind? _fileTabKindAfterPathMove({
    required WorkspaceTabRecord tab,
    required String nextPath,
  }) {
    return switch (tab.kind) {
      WorkspaceTabKind.gitDiff => WorkspaceTabKind.gitDiff,
      WorkspaceTabKind.markdownViewer =>
        isWorkspaceMarkdownFilePath(nextPath)
            ? WorkspaceTabKind.markdownViewer
            : null,
      WorkspaceTabKind.editor =>
        isWorkspacePdfFilePath(nextPath)
            ? WorkspaceTabKind.pdf
            : WorkspaceTabKind.editor,
      WorkspaceTabKind.pdf =>
        isWorkspacePdfFilePath(nextPath)
            ? WorkspaceTabKind.pdf
            : WorkspaceTabKind.editor,
      WorkspaceTabKind.terminal || WorkspaceTabKind.browser => null,
    };
  }

  String _titleForGitDiff({
    required WorkspaceGitDiffScope scope,
    required String? path,
    required GitChangeArea? area,
    required String? root,
  }) {
    return switch (scope) {
      WorkspaceGitDiffScope.all =>
        root == null ? 'All changes' : '${_titleForPath(root)} changes',
      WorkspaceGitDiffScope.fileAll => '${_titleForPath(path!)} changes',
      WorkspaceGitDiffScope.file =>
        '${_titleForPath(path!)} ${area!.label.toLowerCase()}',
    };
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
