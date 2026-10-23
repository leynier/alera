part of 'workspace_git_diff_panel.dart';

extension on _WorkspaceGitDiffPanelState {
  /// The workbench reports a failed tab open through `state.error`, which the
  /// shell shows, so a toast here as well would show the failure twice.
  void _logOpenTabFailure(Object error, StackTrace stackTrace) {
    _gitDiffPanelLogger.warning(
      'Could not open commit diff',
      error,
      stackTrace,
    );
  }

  /// Loads the commit comparison, or shows why it failed and returns null.
  Future<GitCommitCompareResult?> _commitCompareOrReport(
    GitHistoryItem item,
  ) async {
    try {
      return await _commitCompareFor(item);
    } catch (error, stackTrace) {
      _gitDiffPanelLogger.warning(
        'Could not load commit comparison',
        error,
        stackTrace,
      );
      if (mounted) {
        AleraToast.show(context, message: _messageFor(error), tone: .error);
      }
      return null;
    }
  }

  Future<void> _openGitDiff({
    String? relativePath,
    GitChangeArea? area,
    String? gitDiffRoot,
    required WorkspaceGitDiffScope scope,
    bool preview = false,
    bool oppositePanel = false,
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
      oppositePanel: oppositePanel || isModModifierPressed(),
    );
  }

  Future<void> _openCommitFile(
    GitHistoryItem item,
    GitCommitChangeEntry entry,
  ) async {
    final oppositePanel = isModModifierPressed();
    final compare = await _commitCompareOrReport(item);
    if (compare == null || !mounted) {
      return;
    }
    try {
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
        oppositePanel: oppositePanel,
      );
    } catch (error, stackTrace) {
      _logOpenTabFailure(error, stackTrace);
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
    required bool oppositePanel,
  }) {
    Future<void> open({required bool preview}) {
      return onOpen(
        relativePath: relativePath,
        area: area,
        gitDiffRoot: gitDiffRoot,
        scope: scope,
        preview: preview,
        oppositePanel: oppositePanel,
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
    required bool oppositePanel,
  }) async {
    Future<void> open({required bool preview}) {
      return onOpen(
        relativePath: relativePath,
        oldPath: oldPath,
        scope: .file,
        gitDiffRoot: gitDiffRoot,
        commitOid: commitOid,
        parentOid: parentOid,
        compareRef: compareRef,
        subject: subject,
        message: message,
        preview: preview,
        oppositePanel: oppositePanel,
      );
    }

    await open(preview: true);
    if (shouldKeep(keepKey)) {
      await open(preview: false);
    }
  }
}
