import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:uuid/uuid.dart';

part 'workspace_tab_path_moves.dart';

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
      if (tab.gitDiffSource == WorkspaceGitDiffSource.workingTree &&
          tab.gitDiffScope == scope &&
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

  Future<WorkspaceTabRecord> openOrCreateGitCommitDiffTab({
    required String workspaceId,
    String? relativePath,
    String? oldPath,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    required String commitOid,
    String? parentOid,
    required String compareRef,
    String? subject,
    String? message,
  }) async {
    final normalizedPath = relativePath == null
        ? null
        : _normalizeRelativePath(relativePath);
    final normalizedOldPath = oldPath == null
        ? null
        : _normalizeRelativePath(oldPath);
    final normalizedRoot = normalizeSourceControlRootRelativePath(gitDiffRoot);
    if (scope != WorkspaceGitDiffScope.all && normalizedPath == null) {
      throw StateError('Commit diff file tabs require a file path.');
    }
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.kind != WorkspaceTabKind.gitDiff ||
          tab.gitDiffSource != WorkspaceGitDiffSource.commit) {
        continue;
      }
      if (tab.gitDiffScope == scope &&
          tab.filePath == normalizedPath &&
          tab.gitDiffOldPath == normalizedOldPath &&
          tab.gitDiffRoot == normalizedRoot &&
          tab.gitDiffCommitOid == commitOid) {
        return tab;
      }
    }
    final payload = <String, Object?>{
      workspaceTabGitDiffSourcePayloadKey: WorkspaceGitDiffSource.commit.key,
      workspaceTabGitDiffScopePayloadKey: scope.key,
      workspaceTabGitDiffCommitOidPayloadKey: commitOid,
      workspaceTabGitDiffCompareRefPayloadKey: compareRef,
    };
    if (parentOid != null) {
      payload[workspaceTabGitDiffParentOidPayloadKey] = parentOid;
    }
    if (subject != null) {
      payload[workspaceTabGitDiffCommitSubjectPayloadKey] = subject;
    }
    if (message != null) {
      payload[workspaceTabGitDiffCommitMessagePayloadKey] = message;
    }
    if (normalizedRoot != null) {
      payload[workspaceTabGitDiffRootPayloadKey] = normalizedRoot;
    }
    if (normalizedPath != null) {
      payload[workspaceTabFilePathPayloadKey] = normalizedPath;
    }
    if (normalizedOldPath != null) {
      payload[workspaceTabGitDiffOldPathPayloadKey] = normalizedOldPath;
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.gitDiff,
      title: _titleForGitCommitDiff(
        scope: scope,
        path: normalizedPath,
        compareRef: compareRef,
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
      },
    );
    await _repository.upsertWorkspaceTab(next);
    return next;
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

  WorkspaceTabKind _fileBackedKindForPath(String path) {
    if (isWorkspaceMarkdownFilePath(path)) {
      return WorkspaceTabKind.markdownViewer;
    }
    if (isWorkspacePdfFilePath(path)) {
      return WorkspaceTabKind.pdf;
    }
    return WorkspaceTabKind.editor;
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

  String _titleForGitCommitDiff({
    required WorkspaceGitDiffScope scope,
    required String? path,
    required String compareRef,
  }) {
    return switch (scope) {
      WorkspaceGitDiffScope.all => 'Commit $compareRef',
      WorkspaceGitDiffScope.file ||
      WorkspaceGitDiffScope.fileAll => '${_titleForPath(path!)} $compareRef',
    };
  }
}
