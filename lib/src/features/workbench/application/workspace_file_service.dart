import 'dart:io';

import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:path/path.dart' as p;

class WorkspaceFileService {
  const WorkspaceFileService();

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
      workspaceCanonicalPath = await Directory(
        workspacePath,
      ).resolveSymbolicLinks();
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

class ResolvedWorkspaceFile {
  const ResolvedWorkspaceFile({
    required this.path,
    required this.modifiedMicros,
    required this.length,
  });

  final String path;
  final int modifiedMicros;
  final int length;
}

class EditorSessionRegistry {
  final Map<String, EditorDocumentSession> _documents =
      <String, EditorDocumentSession>{};
  final Map<String, EditorSessionHandle> _sessions =
      <String, EditorSessionHandle>{};

  EditorDocumentSession documentFor(String tabId) {
    return _documents.putIfAbsent(tabId, EditorDocumentSession.new);
  }

  void register(String tabId, EditorSessionHandle handle) {
    _sessions[tabId] = handle;
  }

  void unregister(String tabId, EditorSessionHandle handle) {
    if (identical(_sessions[tabId], handle)) {
      _sessions.remove(tabId);
    }
  }

  bool isDirty(String tabId) {
    return _sessions[tabId]?.isDirty() ?? _documents[tabId]?.isDirty ?? false;
  }

  Future<void> save(String tabId) async {
    await _sessions[tabId]?.save();
  }

  Future<int> saveAll(WorkspaceFileService workspaceFiles) async {
    var savedCount = 0;
    final liveSessionIds = _sessions.keys.toList(growable: false);
    for (final tabId in liveSessionIds) {
      if (!isDirty(tabId)) {
        continue;
      }
      await _sessions[tabId]?.save();
      if (!isDirty(tabId)) {
        savedCount += 1;
      }
    }
    for (final entry in _documents.entries) {
      final tabId = entry.key;
      final document = entry.value;
      if (_sessions.containsKey(tabId) ||
          !document.isDirty ||
          !document.canSave ||
          document.workspacePath == null ||
          document.relativePath == null) {
        continue;
      }
      final saved = await workspaceFiles.writeEditorTextFile(
        workspacePath: document.workspacePath!,
        relativePath: document.relativePath!,
        currentDisplayContent: document.currentText ?? '',
        originalRawContent: document.loadedRawText,
        originalDisplayContent: document.loadedText,
        expectedContentToken: document.contentToken,
        overwriteIfChanged: false,
        tabSize: document.tabSize,
      );
      document.acceptSaved(saved);
      savedCount += 1;
    }
    return savedCount;
  }

  Future<void> discard(String tabId) async {
    await _sessions[tabId]?.discard();
  }

  void updateDocumentPathsAfterMove({
    required String workspacePath,
    required String oldRelativePath,
    required String newRelativePath,
  }) {
    for (final document in _documents.values) {
      if (document.workspacePath != workspacePath ||
          document.relativePath == null) {
        continue;
      }
      final nextPath = _replacePathPrefix(
        path: document.relativePath!,
        oldPath: oldRelativePath,
        newPath: newRelativePath,
      );
      if (nextPath != null) {
        document.relativePath = nextPath;
      }
    }
  }

  void forget(String tabId) {
    _sessions.remove(tabId);
    _documents.remove(tabId);
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

class EditorSessionHandle {
  const EditorSessionHandle({
    required this.isDirty,
    required this.save,
    required this.discard,
  });

  final bool Function() isDirty;
  final Future<void> Function() save;
  final Future<void> Function() discard;
}

class EditorDocumentSession {
  String? workspacePath;
  String? relativePath;
  String? loadedRawText;
  String? loadedText;
  String? currentText;
  String? contentToken;
  Object? loadError;
  int tabSize = 4;

  bool get hasSnapshot => currentText != null || loadError != null;

  bool get canSave => loadedText != null && loadError == null;

  bool get isDirty => loadedText != null && currentText != loadedText;

  void attachFile({
    required String workspacePath,
    required String relativePath,
  }) {
    this.workspacePath = workspacePath;
    this.relativePath = relativePath;
  }

  void acceptLoaded(native.WorkspaceEditorTextFile file, {int tabSize = 4}) {
    this.tabSize = tabSize;
    loadedRawText = file.rawContent;
    loadedText = file.displayContent;
    currentText = loadedText;
    contentToken = file.contentToken;
    loadError = null;
  }

  void acceptSaved(native.WorkspaceEditorTextFile file, {int? tabSize}) {
    acceptLoaded(file, tabSize: tabSize ?? this.tabSize);
  }

  void acceptLoadError(Object error) {
    loadedRawText = null;
    loadedText = null;
    currentText = null;
    contentToken = null;
    loadError = error;
  }

  void updateCurrentText(String text) {
    currentText = text;
  }
}
