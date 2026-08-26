part of 'workspace_explorer.dart';

extension _WorkspaceExplorerActions on _WorkspaceExplorerState {
  Future<void> _handleMenuAction(
    BuildContext context,
    tree.VisibleNode node,
    _ExplorerAction action,
  ) async {
    final entry = _entryByNodeId[node.id];
    final targetDir = _isDirectoryEntry(entry)
        ? entry!.relativePath
        : _parentPath(entry?.relativePath ?? '');
    switch (action) {
      case _ExplorerAction.collapse:
        _controller.expansions.setExpanded(node.id, false);
      case _ExplorerAction.newFile:
        await _createEntry(parentPath: targetDir, directory: false);
      case _ExplorerAction.newFolder:
        await _createEntry(parentPath: targetDir, directory: true);
      case _ExplorerAction.rename:
        if (entry != null) {
          await _rename(entry);
        }
      case _ExplorerAction.copy:
        if (entry != null) {
          _setClipboard(_ExplorerClipboard(entry.relativePath, false));
        }
      case _ExplorerAction.cut:
        if (entry != null) {
          _setClipboard(_ExplorerClipboard(entry.relativePath, true));
        }
      case _ExplorerAction.paste:
        await _paste(targetDir);
      case _ExplorerAction.copyPath:
        if (entry != null) {
          await Clipboard.setData(
            ClipboardData(text: _absolutePath(entry.relativePath)),
          );
          _showInfo('Path copied');
        }
      case _ExplorerAction.copyRelativePath:
        if (entry != null) {
          await Clipboard.setData(ClipboardData(text: entry.relativePath));
          _showInfo('Relative path copied');
        }
      case _ExplorerAction.duplicate:
        if (entry != null) {
          await _duplicate(entry);
        }
      case _ExplorerAction.reveal:
        if (entry != null) {
          await _reveal(entry);
        }
      case _ExplorerAction.delete:
        if (entry != null) {
          await _delete(entry);
        }
      case _ExplorerAction.refresh:
        await _refreshDirectory(targetDir);
      case _ExplorerAction.focusSourceControlRoot:
        if (_isDirectoryEntry(entry)) {
          await _focusSourceControlRoot(entry!);
        }
      case _ExplorerAction.clearSourceControlRoot:
        widget.onClearSourceControlRoot?.call();
    }
  }

  Future<void> _handleBackgroundAction(
    BuildContext context,
    _ExplorerAction action,
  ) async {
    switch (action) {
      case _ExplorerAction.newFile:
        await _createEntry(directory: false);
      case _ExplorerAction.newFolder:
        await _createEntry(directory: true);
      case _:
        break;
    }
  }

  Future<void> _createEntry({
    String parentPath = '',
    required bool directory,
  }) async {
    final name = await _promptName(
      title: directory ? 'New folder' : 'New file',
      label: directory ? 'Folder name' : 'File name',
    );
    if (!mounted) {
      return;
    }
    if (name == null) {
      return;
    }
    try {
      if (directory) {
        await _workspaceFiles.createDirectory(
          workspacePath: widget.workspace.path,
          parentRelativePath: parentPath,
          name: name,
        );
      } else {
        await _workspaceFiles.createFile(
          workspacePath: widget.workspace.path,
          parentRelativePath: parentPath,
          name: name,
        );
      }
      if (!mounted) {
        return;
      }
      await _refreshDirectory(parentPath);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _rename(native.WorkspaceFileEntry entry) async {
    final name = await _promptName(
      title: 'Rename',
      label: 'Name',
      initialValue: entry.name,
    );
    if (!mounted) {
      return;
    }
    if (name == null) {
      return;
    }
    try {
      final renamed = await _workspaceFiles.renameEntry(
        workspacePath: widget.workspace.path,
        relativePath: entry.relativePath,
        newName: name,
      );
      if (!mounted) {
        return;
      }
      await widget.onPathMoved(entry.relativePath, renamed.relativePath);
      if (!mounted) {
        return;
      }
      await _refreshDirectory(_parentPath(entry.relativePath));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _paste(String targetDir) async {
    final clipboard = _clipboard;
    if (clipboard == null) {
      return;
    }
    try {
      if (clipboard.cut) {
        await _moveEntry(clipboard.relativePath, targetDir);
      } else {
        await _workspaceFiles.copyEntry(
          workspacePath: widget.workspace.path,
          relativePath: clipboard.relativePath,
          targetParentRelativePath: targetDir,
        );
        if (!mounted) {
          return;
        }
        await _refreshDirectory(targetDir);
      }
      if (!mounted) {
        return;
      }
      if (clipboard.cut) {
        _setClipboard(null);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _duplicate(native.WorkspaceFileEntry entry) async {
    final parentPath = _parentPath(entry.relativePath);
    try {
      await _workspaceFiles.copyEntry(
        workspacePath: widget.workspace.path,
        relativePath: entry.relativePath,
        targetParentRelativePath: parentPath,
      );
      if (!mounted) {
        return;
      }
      await _refreshDirectory(parentPath);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _revealPendingPath({String? relativePath}) async {
    final request = ref.read(workspaceExplorerRevealControllerProvider);
    final targetPath = normalizeWorkspaceRelativePath(
      relativePath ??
          (request?.workspaceId == widget.workspace.id
              ? request?.relativePath
              : null),
    );
    if (targetPath == null) {
      return;
    }
    await _ensureAncestorsLoaded(targetPath);
    if (!mounted) {
      return;
    }
    _rebuildTree();
    final nodeId = _nodeIdForRelativePath(targetPath);
    await _controller.reveal(nodeId: nodeId, select: true);
    if (request != null &&
        request.workspaceId == widget.workspace.id &&
        request.relativePath == targetPath) {
      ref
          .read(workspaceExplorerRevealControllerProvider.notifier)
          .consume(request);
    }
  }

  Future<void> _ensureAncestorsLoaded(String relativePath) async {
    var ancestor = '';
    for (final part in relativePath.split('/')) {
      if (part.isEmpty) {
        continue;
      }
      if (!_childrenByDirectory.containsKey(ancestor)) {
        await _loadDirectory(ancestor);
        if (!mounted) {
          return;
        }
      }
      ancestor = ancestor.isEmpty ? part : '$ancestor/$part';
    }
  }

  String? _nodeIdForRelativePath(String relativePath) {
    for (final binding in _entryByNodeId.entries) {
      if (binding.value.relativePath == relativePath) {
        return binding.key;
      }
    }
    return 'path:$relativePath';
  }

  Future<void> _reveal(native.WorkspaceFileEntry entry) async {
    final result = await _folderOpener.reveal(
      _absolutePath(entry.relativePath),
    );
    if (!mounted) {
      return;
    }
    if (!result.ok) {
      _showError(result.message ?? 'Could not reveal item');
    }
  }

  Future<void> _moveEntry(String relativePath, String targetDir) async {
    try {
      final sourceParent = _parentPath(relativePath);
      final moved = await _workspaceFiles.moveEntry(
        workspacePath: widget.workspace.path,
        relativePath: relativePath,
        targetParentRelativePath: targetDir,
      );
      if (!mounted) {
        return;
      }
      await widget.onPathMoved(relativePath, moved.relativePath);
      if (!mounted) {
        return;
      }
      await _refreshDirectory(sourceParent);
      if (!mounted) {
        return;
      }
      if (sourceParent != targetDir) {
        await _refreshDirectory(targetDir);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _delete(native.WorkspaceFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: 'Delete ${entry.name}',
        message: 'Move this item to the trash?',
        confirmLabel: 'Delete',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    try {
      await _workspaceFiles.deleteEntry(
        workspacePath: widget.workspace.path,
        relativePath: entry.relativePath,
      );
      if (!mounted) {
        return;
      }
      await _refreshDirectory(_parentPath(entry.relativePath));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _saveAllEditors() async {
    try {
      final count = await _editorSessions.saveAll(_workspaceFiles);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: count == 0
            ? 'No unsaved editor files'
            : count == 1
            ? 'Saved 1 editor file'
            : 'Saved $count editor files',
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _refreshDirectory(
    String relativePath, {
    bool refreshGitStatus = true,
  }) async {
    try {
      if (refreshGitStatus) {
        await _refreshGitStatusSnapshot();
      }
      await _loadDirectory(relativePath);
      if (!mounted) {
        return;
      }
      _rebuildTree();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _focusSourceControlRoot(native.WorkspaceFileEntry entry) async {
    final focus = widget.onFocusSourceControlFolder;
    if (focus == null) {
      return;
    }
    try {
      final focused = await focus(entry.relativePath);
      if (!mounted) {
        return;
      }
      if (!focused) {
        _showInfo('Folder is not a Git repository');
      }
    } catch (_) {
      if (mounted) {
        AleraToast.show(
          context,
          message: 'Could not use folder as source control root',
          tone: AleraToastTone.error,
        );
      }
    }
  }

  bool _canDrop(_ExplorerDragData data, String targetPath) {
    final target = _entryByPath[targetPath];
    if (!_isDirectoryEntry(target)) {
      return false;
    }
    return data.relativePath != targetPath &&
        !targetPath.startsWith('${data.relativePath}/');
  }

  void _toggleMode() {
    if (!mounted) {
      return;
    }
    widget.onModeChanged(
      widget.mode == WorkspaceExplorerMode.hideIgnored
          ? WorkspaceExplorerMode.showAll
          : WorkspaceExplorerMode.hideIgnored,
    );
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    AleraToast.show(context, message: message);
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ExplorerNameDialog(
        title: title,
        label: label,
        initialValue: initialValue,
      ),
    );
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: _errorMessage(error),
      tone: AleraToastTone.error,
    );
  }

  String _errorMessage(Object error) {
    if (error is native.WorkspaceFileError) {
      return switch (error.kind) {
        native.WorkspaceFileErrorKind.alreadyExists => 'Item already exists',
        native.WorkspaceFileErrorKind.protectedPath => 'Path is protected',
        native.WorkspaceFileErrorKind.outsideWorkspace =>
          'Path is outside the workspace',
        native.WorkspaceFileErrorKind.unsupported => 'Operation is unsupported',
        native.WorkspaceFileErrorKind.notFound => 'Item not found',
        native.WorkspaceFileErrorKind.conflict => 'File changed on disk',
        _ => 'File operation failed',
      };
    }
    return 'File operation failed';
  }

  String _parentPath(String relativePath) {
    final index = relativePath.lastIndexOf('/');
    return index < 0 ? '' : relativePath.substring(0, index);
  }

  String _absolutePath(String relativePath) {
    return terminalAbsolutePath(
      rootPath: widget.workspace.path,
      relativePath: relativePath,
    );
  }
}
