import 'dart:io';

import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/rust/api/merman_viewer.dart' as merman_native;
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

part 'editor_session_registry.dart';

class const WorkspaceFileService() {
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspacePath,
    required String relativePath,
    required bool hideIgnored,
  }) {
    return native.listWorkspaceChildren(
      workspacePath: workspacePath,
      relativePath: relativePath,
      hideIgnored: hideIgnored,
    );
  }

  Future<native.WorkspaceQuickOpenSession> startQuickOpenSession({
    required String workspacePath,
  }) {
    return native.startWorkspaceQuickOpenSession(workspacePath: workspacePath);
  }

  Future<List<native.WorkspaceQuickOpenMatch>> searchQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
    required String query,
    int limit = 50,
  }) {
    return native.searchWorkspaceQuickOpenSession(
      session: session,
      query: query,
      limit: limit,
    );
  }

  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  }) {
    return native.stopWorkspaceQuickOpenSession(session: session);
  }

  Future<List<native.CodexSavedPrompt>> listCodexSavedPrompts({
    required String workspacePath,
  }) => native.listCodexSavedPrompts(workspacePath: workspacePath);

  List<native.WorkspaceFileEntry> applyGitStatusSnapshot(
    List<native.WorkspaceFileEntry> entries,
    GitExplorerStatusSnapshot snapshot,
  ) {
    return entries
        .map((entry) {
          final status = snapshot.statusFor(entry.relativePath);
          if (status == null) {
            return entry;
          }
          return native.WorkspaceFileEntry(
            relativePath: entry.relativePath,
            name: entry.name,
            kind: entry.kind,
            size: entry.size,
            modifiedMillis: entry.modifiedMillis,
            contentToken: entry.contentToken,
            isIgnored: entry.isIgnored,
            isHidden: entry.isHidden,
            isSymlink: entry.isSymlink,
            isProtected: entry.isProtected,
            hasChildrenHint: entry.hasChildrenHint,
            gitStatus: switch (status) {
              GitExplorerStatus.untracked =>
                native.WorkspaceFileGitStatus.untracked,
              GitExplorerStatus.added => native.WorkspaceFileGitStatus.added,
              GitExplorerStatus.modified =>
                native.WorkspaceFileGitStatus.modified,
            },
          );
        })
        .toList(growable: false);
  }

  Future<native.WorkspaceExplorerTreeProjection> projectExplorerTree({
    required String workspaceName,
    required String workspacePath,
    required List<native.WorkspaceExplorerDirectoryChildren> directories,
    native.WorkspaceExplorerDirectoryChildren? replacement,
  }) {
    return native.projectWorkspaceExplorerTree(
      workspaceName: workspaceName,
      workspacePath: workspacePath,
      directories: directories,
      replacement: replacement,
    );
  }

  Future<native.WorkspaceExplorerWatcherHandle> startExplorerWatcher({
    required String workspacePath,
  }) {
    return native.startWorkspaceExplorerWatcher(workspacePath: workspacePath);
  }

  Future<void> updateExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
    required List<String> watchedRelativePaths,
  }) {
    return native.updateWorkspaceExplorerWatcher(
      handle: handle,
      watchedRelativePaths: watchedRelativePaths,
    );
  }

  Stream<native.WorkspaceExplorerWatchBatch> watchExplorerEvents({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) {
    return native.watchWorkspaceExplorerEvents(handle: handle);
  }

  Future<void> stopExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) {
    return native.stopWorkspaceExplorerWatcher(handle: handle);
  }

  Future<native.WorkspaceTextFile> readTextFile({
    required String workspacePath,
    required String relativePath,
  }) {
    return native.readWorkspaceTextFile(
      workspacePath: workspacePath,
      relativePath: relativePath,
    );
  }

  Future<merman_native.MermanWorkspaceRender> renderMermanWorkspaceFile({
    required String workspacePath,
    required String relativePath,
  }) {
    return merman_native.renderMermanWorkspaceFile(
      workspacePath: workspacePath,
      relativePath: relativePath,
    );
  }

  Future<native.WorkspaceEditorTextFile> readEditorTextFile({
    required String workspacePath,
    required String relativePath,
    required int tabSize,
  }) {
    return native.readWorkspaceEditorTextFile(
      workspacePath: workspacePath,
      relativePath: relativePath,
      tabSize: tabSize,
    );
  }

  Future<native.WorkspaceTextFile> writeTextFile({
    required String workspacePath,
    required String relativePath,
    required String content,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
  }) {
    return native.writeWorkspaceTextFile(
      workspacePath: workspacePath,
      relativePath: relativePath,
      content: content,
      expectedContentToken: expectedContentToken,
      overwriteIfChanged: overwriteIfChanged,
    );
  }

  Future<native.WorkspaceEditorTextFile> writeEditorTextFile({
    required String workspacePath,
    required String relativePath,
    required String currentDisplayContent,
    required String? originalRawContent,
    required String? originalDisplayContent,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
    required int tabSize,
  }) {
    return native.writeWorkspaceEditorTextFile(
      workspacePath: workspacePath,
      relativePath: relativePath,
      currentDisplayContent: currentDisplayContent,
      originalRawContent: originalRawContent,
      originalDisplayContent: originalDisplayContent,
      expectedContentToken: expectedContentToken,
      overwriteIfChanged: overwriteIfChanged,
      tabSize: tabSize,
    );
  }

  Future<native.WorkspaceFileEntry> createFile({
    required String workspacePath,
    required String parentRelativePath,
    required String name,
  }) {
    return native.createWorkspaceFile(
      workspacePath: workspacePath,
      parentRelativePath: parentRelativePath,
      name: name,
    );
  }

  Future<native.WorkspaceFileEntry> createDirectory({
    required String workspacePath,
    required String parentRelativePath,
    required String name,
  }) {
    return native.createWorkspaceDirectory(
      workspacePath: workspacePath,
      parentRelativePath: parentRelativePath,
      name: name,
    );
  }

  Future<native.WorkspaceFileEntry> renameEntry({
    required String workspacePath,
    required String relativePath,
    required String newName,
  }) {
    return native.renameWorkspaceEntry(
      workspacePath: workspacePath,
      relativePath: relativePath,
      newName: newName,
    );
  }

  Future<native.WorkspaceFileEntry> copyEntry({
    required String workspacePath,
    required String relativePath,
    required String targetParentRelativePath,
  }) {
    return native.copyWorkspaceEntry(
      workspacePath: workspacePath,
      relativePath: relativePath,
      targetParentRelativePath: targetParentRelativePath,
    );
  }

  Future<native.WorkspaceFileEntry> moveEntry({
    required String workspacePath,
    required String relativePath,
    required String targetParentRelativePath,
  }) {
    return native.moveWorkspaceEntry(
      workspacePath: workspacePath,
      relativePath: relativePath,
      targetParentRelativePath: targetParentRelativePath,
    );
  }

  Future<void> deleteEntry({
    required String workspacePath,
    required String relativePath,
    bool useTrash = true,
  }) {
    return native.deleteWorkspaceEntry(
      workspacePath: workspacePath,
      relativePath: relativePath,
      useTrash: useTrash,
    );
  }

  Future<ResolvedWorkspaceFile> resolveWorkspaceFilePath({
    required String workspacePath,
    required String relativePath,
  }) async {
    final normalizedRelativePath = _normalizeRelativeFilePath(relativePath);
    late final String workspaceCanonicalPath;
    try {
      workspaceCanonicalPath = await Directory(workspacePath)
          .resolveSymbolicLinks();
    } on FileSystemException catch (error) {
      throw native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.io,
        context: error.message,
      );
    }

    final requestedPath = p.join(
      workspaceCanonicalPath,
      normalizedRelativePath,
    );
    late final String fileCanonicalPath;
    try {
      fileCanonicalPath = await File(requestedPath).resolveSymbolicLinks();
    } on FileSystemException catch (error) {
      throw native.WorkspaceFileError(
        kind: error.osError == null
            ? native.WorkspaceFileErrorKind.io
            : native.WorkspaceFileErrorKind.notFound,
        context: relativePath,
      );
    }

    if (!p.isWithin(workspaceCanonicalPath, fileCanonicalPath)) {
      throw native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.outsideWorkspace,
        context: relativePath,
      );
    }

    final stat = await File(fileCanonicalPath).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.unsupported,
        context: relativePath,
      );
    }
    return ResolvedWorkspaceFile(
      path: fileCanonicalPath,
      modifiedMicros: stat.modified.microsecondsSinceEpoch,
      length: stat.size,
    );
  }

  String _normalizeRelativeFilePath(String relativePath) {
    if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
      throw native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.invalidPath,
        context: relativePath,
      );
    }
    final normalized = p.normalize(relativePath.replaceAll(r'\', p.separator));
    final parts = p.split(normalized);
    if (normalized == '.' || parts.contains('..')) {
      throw native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.invalidPath,
        context: relativePath,
      );
    }
    return normalized;
  }
}

class const ResolvedWorkspaceFile({
  required final String path,
  required final int modifiedMicros,
  required final int length,
});
