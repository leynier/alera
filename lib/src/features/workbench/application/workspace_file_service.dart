import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/foundation.dart';

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

  List<String> dirtyPathsFor({
    required String workspacePath,
    required Iterable<String> relativePaths,
  }) {
    final candidates = relativePaths.toSet();
    final dirtyPaths = <String>{};
    for (final entry in _documents.entries) {
      final tabId = entry.key;
      final document = entry.value;
      final relativePath = document.relativePath;
      if (document.workspacePath != workspacePath ||
          relativePath == null ||
          !candidates.contains(relativePath)) {
        continue;
      }
      if (isDirty(tabId)) {
        dirtyPaths.add(relativePath);
      }
    }
    final sorted = dirtyPaths.toList()..sort();
    return sorted;
  }

  void reveal(String tabId, WorkspaceEditorRevealTarget target) {
    final handle = _sessions[tabId];
    if (handle != null) {
      handle.reveal?.call(target);
      return;
    }
    documentFor(tabId).pendingReveal = target;
  }

  WorkspaceEditorRevealTarget? takePendingReveal(String tabId) {
    final document = _documents[tabId];
    final target = document?.pendingReveal;
    if (document != null) {
      document.pendingReveal = null;
    }
    return target;
  }

  void reloadCleanFiles({
    required String workspacePath,
    required Iterable<String> relativePaths,
  }) {
    final candidates = relativePaths.toSet();
    for (final entry in _documents.entries) {
      final tabId = entry.key;
      final document = entry.value;
      final relativePath = document.relativePath;
      if (document.workspacePath != workspacePath ||
          relativePath == null ||
          !candidates.contains(relativePath) ||
          isDirty(tabId)) {
        continue;
      }
      final handle = _sessions[tabId];
      if (handle != null) {
        handle.reload?.call();
      } else {
        document.clearSnapshot();
      }
    }
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
    this.reveal,
    this.reload,
  });

  final bool Function() isDirty;
  final Future<void> Function() save;
  final Future<void> Function() discard;
  final void Function(WorkspaceEditorRevealTarget target)? reveal;
  final VoidCallback? reload;
}

class WorkspaceEditorRevealTarget {
  const WorkspaceEditorRevealTarget({
    required this.line,
    required this.column,
    required this.matchLength,
  });

  final int line;
  final int column;
  final int matchLength;
}

class EditorDocumentSession {
  String? workspacePath;
  String? relativePath;
  String? loadedRawText;
  String? loadedText;
  String? currentText;
  String? contentToken;
  Object? loadError;
  WorkspaceEditorRevealTarget? pendingReveal;
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

  void clearSnapshot() {
    loadedRawText = null;
    loadedText = null;
    currentText = null;
    contentToken = null;
    loadError = null;
  }

  void updateCurrentText(String text) {
    currentText = text;
  }
}
