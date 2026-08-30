part of 'workspace_file_service.dart';

class EditorSessionRegistry extends ChangeNotifier {
  final Map<String, EditorDocumentSession> _documents =
      <String, EditorDocumentSession>{};
  final Map<String, EditorSessionHandle> _sessions =
      <String, EditorSessionHandle>{};
  final Map<String, _EditorDocumentPath> _pathByTabId =
      <String, _EditorDocumentPath>{};
  final Map<_EditorDocumentPath, Set<String>> _tabIdsByPath =
      <_EditorDocumentPath, Set<String>>{};
  final Map<_EditorDocumentPath, _EditorPathChangeNotifier> _pathNotifiers =
      <_EditorDocumentPath, _EditorPathChangeNotifier>{};

  EditorDocumentSession documentFor(String tabId) {
    return _documents.putIfAbsent(
      tabId,
      () => EditorDocumentSession(onChanged: () => _documentChanged(tabId)),
    );
  }

  Listenable documentChangesForPath({
    required String workspacePath,
    required String relativePath,
  }) {
    final path = _EditorDocumentPath(workspacePath, relativePath);
    return _pathNotifiers.putIfAbsent(path, _EditorPathChangeNotifier.new);
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

  String? dirtyTextForPath({
    required String workspacePath,
    required String relativePath,
  }) {
    final path = _EditorDocumentPath(workspacePath, relativePath);
    final tabIds = _tabIdsByPath[path];
    if (tabIds == null) {
      return null;
    }
    for (final tabId in tabIds) {
      final document = _documents[tabId];
      if (document != null &&
          document.loadError == null &&
          document.currentText != null &&
          isDirty(tabId)) {
        return document.currentText;
      }
    }
    return null;
  }

  void reveal(String tabId, WorkspaceEditorRevealTarget target) {
    final handle = _sessions[tabId];
    final reveal = handle?.reveal;
    if (reveal != null) {
      reveal(target);
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
      final reload = handle?.reload;
      if (reload != null) {
        reload();
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
        document.attachFile(
          workspacePath: workspacePath,
          relativePath: nextPath,
        );
      }
    }
  }

  void forget(String tabId) {
    final hadSession = _sessions.remove(tabId) != null;
    final hadDocument = _documents.remove(tabId) != null;
    final path = _pathByTabId.remove(tabId);
    if (path != null) {
      final tabIds = _tabIdsByPath[path];
      tabIds?.remove(tabId);
      if (tabIds?.isEmpty ?? false) {
        _tabIdsByPath.remove(path);
      }
      _pathNotifiers[path]?.notifyListeners();
      _maybeReleasePathNotifier(path);
    }
    if (hadSession || hadDocument) {
      notifyListeners();
    }
  }

  /// Drops a path notifier once nothing references its path anymore.
  ///
  /// Without this the map grows with every file ever opened for the lifetime
  /// of the session. A notifier still held by a mounted viewer keeps its
  /// listeners, so it stays; a rebuilt viewer obtains a fresh one through
  /// [documentChangesForPath].
  void _maybeReleasePathNotifier(_EditorDocumentPath path) {
    final notifier = _pathNotifiers[path];
    if (notifier == null ||
        notifier.hasActiveListeners ||
        _tabIdsByPath.containsKey(path)) {
      return;
    }
    _pathNotifiers.remove(path);
  }

  void _documentChanged(String tabId) {
    final document = _documents[tabId];
    if (document == null) {
      return;
    }
    final previousPath = _pathByTabId[tabId];
    final nextPath = switch ((document.workspacePath, document.relativePath)) {
      (final String workspacePath, final String relativePath) =>
        _EditorDocumentPath(workspacePath, relativePath),
      _ => null,
    };
    if (previousPath != nextPath) {
      if (previousPath != null) {
        final previousTabIds = _tabIdsByPath[previousPath];
        previousTabIds?.remove(tabId);
        if (previousTabIds?.isEmpty ?? false) {
          _tabIdsByPath.remove(previousPath);
        }
        _pathNotifiers[previousPath]?.notifyListeners();
        _maybeReleasePathNotifier(previousPath);
      }
      if (nextPath != null) {
        _pathByTabId[tabId] = nextPath;
        _tabIdsByPath.putIfAbsent(nextPath, () => <String>{}).add(tabId);
      } else {
        _pathByTabId.remove(tabId);
      }
    }
    if (nextPath != null) {
      _pathNotifiers[nextPath]?.notifyListeners();
    }
    notifyListeners();
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

/// Exposes the protected listener count so the registry can drop notifiers
/// nobody references anymore.
class _EditorPathChangeNotifier extends ChangeNotifier {
  bool get hasActiveListeners => hasListeners;
}

class const _EditorDocumentPath(
  final String workspacePath,
  final String relativePath,
) {
  @override
  bool operator ==(Object other) {
    return other is _EditorDocumentPath &&
        other.workspacePath == workspacePath &&
        other.relativePath == relativePath;
  }

  @override
  int get hashCode => Object.hash(workspacePath, relativePath);
}

class const EditorSessionHandle({
  required final bool Function() isDirty,
  required final Future<void> Function() save,
  required final Future<void> Function() discard,
  final void Function(WorkspaceEditorRevealTarget target)? reveal,
  final VoidCallback? reload,
});

class const WorkspaceEditorRevealTarget({
  required final int line,
  required final int column,
  required final int matchLength,
});

class EditorDocumentSession({final VoidCallback? _onChanged}) {
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
    if (this.workspacePath == workspacePath &&
        this.relativePath == relativePath) {
      return;
    }
    this.workspacePath = workspacePath;
    this.relativePath = relativePath;
    _notifyChanged();
  }

  void acceptLoaded(native.WorkspaceEditorTextFile file, {int tabSize = 4}) {
    this.tabSize = tabSize;
    loadedRawText = file.rawContent;
    loadedText = file.displayContent;
    currentText = loadedText;
    contentToken = file.contentToken;
    loadError = null;
    _notifyChanged();
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
    _notifyChanged();
  }

  void clearSnapshot() {
    loadedRawText = null;
    loadedText = null;
    currentText = null;
    contentToken = null;
    loadError = null;
    _notifyChanged();
  }

  void updateCurrentText(String text) {
    if (currentText == text) {
      return;
    }
    currentText = text;
    _notifyChanged();
  }

  void _notifyChanged() {
    _onChanged?.call();
  }
}
