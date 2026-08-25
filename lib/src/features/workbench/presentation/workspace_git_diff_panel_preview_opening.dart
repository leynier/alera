part of 'workspace_git_diff_panel.dart';

extension on _WorkspaceGitDiffPanelState {
  Future<void> _openGitDiff({
    String? relativePath,
    GitChangeArea? area,
    String? gitDiffRoot,
    required WorkspaceGitDiffScope scope,
    bool preview = false,
  }) {
    assert(
      gitDiffRoot == null ||
          gitDiffRoot == widget.sourceControlScope.relativeRoot,
    );
    return _previewOpening.openWorkingTree(
      onOpen: widget.onOpenGitDiff,
      relativePath: widget.sourceControlScope.toWorkspaceRelativePath(
        relativePath,
      ),
      area: area,
      gitDiffRoot: widget.sourceControlScope.relativeRoot,
      scope: scope,
      preview: preview,
    );
  }

  Future<void> _openCommitFile(
    GitHistoryItem item,
    GitCommitChangeEntry entry,
  ) async {
    try {
      final compare = await _commitCompareFor(item);
      if (!mounted) {
        return;
      }
      await _previewOpening.openCommitFile(
        onOpen: widget.onOpenGitCommitDiff,
        relativePath: widget.sourceControlScope.toWorkspaceRelativePath(
          entry.path,
        ),
        oldPath: widget.sourceControlScope.toWorkspaceRelativePath(
          entry.oldPath,
        ),
        gitDiffRoot: widget.sourceControlScope.relativeRoot,
        commitOid: compare.summary.commitOid,
        parentOid: compare.summary.parentOid,
        compareRef: compare.summary.compareRef,
        subject: item.subject,
        message: item.message,
        keepKey: 'commit:${item.id}:${entry.path}',
      );
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: _messageFor(error),
          tone: AleraToastTone.error,
        );
      }
    }
  }
}

final class _GitDiffPreviewOpening {
  String? _lastKey;
  DateTime? _lastAt;

  bool shouldKeep(String key) {
    final now = DateTime.now();
    if (_lastKey == key &&
        _lastAt != null &&
        now.difference(_lastAt!) <= kDoubleTapTimeout) {
      _lastKey = null;
      _lastAt = null;
      return true;
    }
    _lastKey = key;
    _lastAt = now;
    return false;
  }

  Future<void> openWorkingTree({
    required OpenGitDiffTabCallback onOpen,
    required String? relativePath,
    GitChangeArea? area,
    required String? gitDiffRoot,
    required WorkspaceGitDiffScope scope,
    required bool preview,
  }) {
    Future<void> open({required bool preview}) {
      return onOpen(
        relativePath: relativePath,
        area: area,
        gitDiffRoot: gitDiffRoot,
        scope: scope,
        preview: preview,
      );
    }

    if (!preview) {
      return open(preview: false);
    }
    final keep = shouldKeep(
      'working:${scope.key}:${area?.key ?? ''}:${relativePath ?? ''}',
    );
    if (!keep) {
      return open(preview: true);
    }
    return open(preview: true).whenComplete(() => open(preview: false));
  }

  Future<void> openCommitFile({
    required OpenGitCommitDiffTabCallback onOpen,
    required String? relativePath,
    required String? oldPath,
    required String? gitDiffRoot,
    required String commitOid,
    required String? parentOid,
    required String compareRef,
    required String? subject,
    required String? message,
    required String keepKey,
  }) async {
    Future<void> open({required bool preview}) {
      return onOpen(
        relativePath: relativePath,
        oldPath: oldPath,
        scope: WorkspaceGitDiffScope.file,
        gitDiffRoot: gitDiffRoot,
        commitOid: commitOid,
        parentOid: parentOid,
        compareRef: compareRef,
        subject: subject,
        message: message,
        preview: preview,
      );
    }

    await open(preview: true);
    if (shouldKeep(keepKey)) {
      await open(preview: false);
    }
  }
}
