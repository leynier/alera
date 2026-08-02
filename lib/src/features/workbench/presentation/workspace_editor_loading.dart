part of 'workspace_editor_surface.dart';

extension _WorkspaceEditorLoading on _WorkspaceEditorSurfaceState {
  Future<void> _load() async {
    _autosave.cancelPending();
    final requestId = ++_loadRequestId;
    final workspacePath = widget.workspace.path;
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      if (mounted) {
        _setEditorState(() {
          _loading = false;
          _loadError = null;
        });
      }
      return;
    }
    _setEditorState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final tabSize = _currentEditorTabSize();
      final file = await _workspaceFiles.readEditorTextFile(
        workspacePath: workspacePath,
        relativePath: filePath,
        tabSize: tabSize,
      );
      if (!_isCurrentLoadRequest(requestId, workspacePath, filePath)) {
        return;
      }
      _document.acceptLoaded(file, tabSize: tabSize);
      _controller.text = _document.currentText ?? '';
    } catch (error) {
      if (!_isCurrentLoadRequest(requestId, workspacePath, filePath)) {
        return;
      }
      _document.acceptLoadError(error);
      _loadError = error;
    } finally {
      if (_isCurrentLoadRequest(requestId, workspacePath, filePath)) {
        _setEditorState(() => _loading = false);
        _applyPendingReveal();
        _autosave.notifyStateChanged();
      }
    }
  }

  void _restoreDocumentOrLoad() {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      _invalidatePendingLoads();
      _autosave.cancelPending();
      _loading = false;
      _loadError = null;
      return;
    }
    _document.attachFile(
      workspacePath: widget.workspace.path,
      relativePath: filePath,
    );
    if (_document.hasSnapshot) {
      _invalidatePendingLoads();
      _controller.text = _document.currentText ?? '';
      _loadError = _document.loadError;
      _loading = false;
      _applyPendingReveal();
      _autosave.notifyStateChanged();
      return;
    }
    _loading = true;
    _loadError = null;
    unawaited(_load());
  }

  bool _isCurrentLoadRequest(
    int requestId,
    String workspacePath,
    String filePath,
  ) {
    return mounted &&
        workspaceEditorLoadRequestMatches(
          requestId: requestId,
          currentRequestId: _loadRequestId,
          workspacePath: workspacePath,
          activeWorkspacePath: widget.workspace.path,
          filePath: filePath,
          activeFilePath: widget.tab.filePath,
        );
  }

  void _invalidatePendingLoads() {
    _loadRequestId += 1;
  }
}

@visibleForTesting
bool workspaceEditorLoadRequestMatches({
  required int requestId,
  required int currentRequestId,
  required String workspacePath,
  required String activeWorkspacePath,
  required String filePath,
  required String? activeFilePath,
}) {
  return requestId == currentRequestId &&
      workspacePath == activeWorkspacePath &&
      filePath == activeFilePath;
}
