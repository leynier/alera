part of 'workspace_editor_surface.dart';

extension _WorkspaceEditorSave on _WorkspaceEditorSurfaceState {
  Future<void> _save() async {
    final filePath = widget.tab.filePath;
    if (filePath == null || _loading || _saving) {
      return;
    }
    final loadError = _loadError;
    if (loadError != null) {
      _showToast(_messageFor(loadError), tone: AleraToastTone.error);
      return;
    }
    if (!_document.canSave || !mounted) {
      return;
    }
    final contentBeingSaved = _controller.text;
    _setEditorState(() => _saving = true);
    try {
      final saved = await _write(overwriteIfChanged: false);
      if (!mounted) {
        return;
      }
      _acceptSavedIfUnchanged(saved, contentBeingSaved);
      _autosave.resume();
      _showToast('File saved');
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is native.WorkspaceFileError &&
          error.kind == native.WorkspaceFileErrorKind.conflict) {
        _autosave.pause();
        await _resolveSaveConflict();
      } else {
        _showToast(_messageFor(error), tone: AleraToastTone.error);
      }
    } finally {
      if (mounted) {
        _setEditorState(() => _saving = false);
      }
      _autosave.notifyStateChanged();
    }
  }

  Future<void> _saveAutomatically() async {
    final filePath = widget.tab.filePath;
    if (!mounted ||
        filePath == null ||
        _loading ||
        _saving ||
        _loadError != null ||
        !_document.canSave) {
      return;
    }
    final contentBeingSaved = _controller.text;
    _setEditorState(() => _saving = true);
    try {
      final saved = await _write(overwriteIfChanged: false);
      if (!mounted) {
        return;
      }
      _acceptSavedIfUnchanged(saved, contentBeingSaved);
    } finally {
      if (mounted) {
        _setEditorState(() => _saving = false);
      }
    }
  }

  Future<void> _discardChanges() async {
    if (_loading || _saving || !_document.canSave) {
      return;
    }
    final loadedText = _document.loadedText;
    if (loadedText == null) {
      return;
    }
    _document.updateCurrentText(loadedText);
    _controller.text = loadedText;
    _undoController.clear();
    if (mounted) {
      _setEditorState(() {});
      _showToast('Changes discarded');
    }
    _autosave.notifyStateChanged();
  }

  Future<bool> _resolveSaveConflict() async {
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (context) => const AleraConfirmDialog(
        title: 'File changed on disk',
        message: 'Overwrite the file with the editor contents?',
        confirmLabel: 'Overwrite',
        destructive: true,
      ),
    );
    if (overwrite != true || !mounted) {
      return false;
    }
    final contentBeingSaved = _controller.text;
    try {
      final saved = await _write(overwriteIfChanged: true);
      if (!mounted) {
        return false;
      }
      _acceptSavedIfUnchanged(saved, contentBeingSaved);
      _autosave.resume();
      _showToast('File overwritten');
      return true;
    } catch (error) {
      if (mounted) {
        _showToast(_messageFor(error), tone: AleraToastTone.error);
      }
      return false;
    }
  }

  Future<native.WorkspaceEditorTextFile> _write({
    required bool overwriteIfChanged,
  }) {
    return _workspaceFiles.writeEditorTextFile(
      workspacePath: widget.workspace.path,
      relativePath: widget.tab.filePath!,
      currentDisplayContent: _controller.text,
      originalRawContent: _document.loadedRawText,
      originalDisplayContent: _document.loadedText,
      expectedContentToken: _document.contentToken,
      overwriteIfChanged: overwriteIfChanged,
      tabSize: _currentEditorTabSize(),
    );
  }

  void _acceptSaved(native.WorkspaceEditorTextFile saved) {
    _document.acceptSaved(saved, tabSize: _currentEditorTabSize());
    _controller.text = _document.currentText ?? '';
  }

  void _acceptSavedIfUnchanged(
    native.WorkspaceEditorTextFile saved,
    String contentBeingSaved,
  ) {
    if (_controller.text == contentBeingSaved) {
      _acceptSaved(saved);
      return;
    }
    final currentText = _controller.text;
    _document.acceptSaved(saved, tabSize: _currentEditorTabSize());
    _document.updateCurrentText(currentText);
  }

  bool _isReadyForAutosave() {
    return mounted &&
        !_loading &&
        !_saving &&
        _loadError == null &&
        _document.canSave;
  }

  void _handleControllerChanged() {
    final wasDirty = _document.isDirty;
    _document.updateCurrentText(_controller.text);
    if (!_loading && widget.tab.isPreview && !wasDirty && _document.isDirty) {
      widget.onKeepPreview?.call();
    }
    _autosave.notifyTextChanged();
    _refreshStateSafely();
  }

  void _handleAutosaveError(Object error, StackTrace stackTrace) {
    if (!mounted) {
      return;
    }
    if (error is native.WorkspaceFileError &&
        error.kind == native.WorkspaceFileErrorKind.conflict) {
      _showToast('Autosave paused because the file changed on disk.');
      unawaited(_resolveSaveConflict());
      return;
    }
    _showToast(
      'Autosave paused: ${_messageFor(error)}',
      tone: AleraToastTone.error,
    );
  }
}
