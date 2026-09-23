part of 'workspace_tab_service.dart';

/// Retargeting open tabs after a file or folder moves on disk.
///
/// Split out of `workspace_tab_service.dart`, which keeps opening, creating,
/// renaming and closing tabs.

class const WorkspaceFileTabPathMoveResult({
  required final List<WorkspaceTabRecord> updatedTabs,
  required final List<String> closedTabIds,
}) {
  List<String> get removedTabIds => closedTabIds;

  bool get isEmpty => updatedTabs.isEmpty && closedTabIds.isEmpty;
}

extension WorkspaceTabPathMoves on WorkspaceTabService {
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
        title: _isCommitBackedGitDiff(tab)
            ? tab.title
            : _titleForGitDiff(
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
      if (_isCommitBackedGitDiff(tab)) {
        continue;
      }
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
      updatedTabs: List<WorkspaceTabRecord>.unmodifiableOf(updatedById.values),
      closedTabIds: List<String>.unmodifiableOf(closed),
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

  bool _isFileTabKind(WorkspaceTabKind kind) => switch (kind) {
    WorkspaceTabKind.editor ||
    WorkspaceTabKind.markdownViewer ||
    WorkspaceTabKind.pdf ||
    WorkspaceTabKind.gitDiff => true,
    WorkspaceTabKind.terminal => false,
  };

  bool _isRetargetableFileBackedTab(WorkspaceTabRecord tab) {
    return tab.kind == WorkspaceTabKind.editor ||
        tab.kind == WorkspaceTabKind.pdf ||
        tab.kind == WorkspaceTabKind.markdownViewer;
  }

  bool _isCommitBackedGitDiff(WorkspaceTabRecord tab) {
    return tab.kind == WorkspaceTabKind.gitDiff &&
        tab.gitDiffSource != WorkspaceGitDiffSource.workingTree;
  }

  WorkspaceTabKind? _fileTabKindAfterPathMove({
    required WorkspaceTabRecord tab,
    required String nextPath,
  }) => switch (tab.kind) {
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
    WorkspaceTabKind.terminal => null,
  };

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
