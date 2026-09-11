part of 'workbench_controller.dart';

mixin _WorkbenchControllerSourceControlRoot
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerViewPrefs {
  Future<bool> focusSourceControlFolder({
    required Workspace workspace,
    required String relativePath,
  }) async {
    final project = _projectById(state.projects, workspace.projectId);
    if (project == null || !project.isFolder) {
      return false;
    }
    if (state.activeProjectId != project.id ||
        state.activeWorkspaceId != workspace.id) {
      return false;
    }
    final normalized = normalizeSourceControlRootRelativePath(relativePath);
    if (normalized == null) {
      return false;
    }
    final path = sourceControlRootAbsolutePath(
      workspacePath: workspace.path,
      relativeRoot: normalized,
    );
    if (!_hasDirectGitEntry(path)) {
      return false;
    }
    final isRepository = await ref
        .read(gitBackendProvider)
        .isGitRepository(path);
    if (!isRepository) {
      return false;
    }
    if (state.activeProjectId != project.id ||
        state.activeWorkspaceId != workspace.id) {
      return false;
    }
    final nextRoots = <String, String>{
      ...state.viewPrefs.sourceControlRootByWorkspaceId,
      workspace.id: normalized,
    };
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        sourceControlRootByWorkspaceId: nextRoots,
        activeContextPanelTab: .gitDiff,
        rightSidebarVisible: true,
      ),
    );
    state = state.copyWith(error: null);
    if (state.isExperimentalLayout) setContextPanelTab(.gitDiff);
    return true;
  }

  bool _hasDirectGitEntry(String path) {
    final gitEntryPath = p.join(path, '.git');
    return Directory(gitEntryPath).existsSync() ||
        File(gitEntryPath).existsSync();
  }

  void clearFocusedSourceControlFolder({required Workspace workspace}) {
    if (!state.viewPrefs.sourceControlRootByWorkspaceId.containsKey(
      workspace.id,
    )) {
      return;
    }
    final nextRoots = Map<String, String>.from(
      state.viewPrefs.sourceControlRootByWorkspaceId,
    )..remove(workspace.id);
    _updateViewPrefs(
      state.viewPrefs.copyWith(sourceControlRootByWorkspaceId: nextRoots),
    );
  }

  void syncSourceControlRootAfterPathMove({
    required Workspace workspace,
    required String oldRelativePath,
    required String newRelativePath,
  }) {
    final current =
        state.viewPrefs.sourceControlRootByWorkspaceId[workspace.id];
    if (current == null) {
      return;
    }
    final nextRoot = _replaceSourceControlPathPrefix(
      path: current,
      oldPath: oldRelativePath,
      newPath: newRelativePath,
    );
    if (nextRoot == null || nextRoot == current) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        sourceControlRootByWorkspaceId: <String, String>{
          ...state.viewPrefs.sourceControlRootByWorkspaceId,
          workspace.id: nextRoot,
        },
      ),
    );
  }

  String? _replaceSourceControlPathPrefix({
    required String path,
    required String oldPath,
    required String newPath,
  }) {
    final normalizedPath = normalizeSourceControlRootRelativePath(path);
    final normalizedOld = normalizeSourceControlRootRelativePath(oldPath);
    final normalizedNew = normalizeSourceControlRootRelativePath(newPath);
    if (normalizedPath == null ||
        normalizedOld == null ||
        normalizedNew == null) {
      return null;
    }
    if (normalizedPath == normalizedOld) {
      return normalizedNew;
    }
    final prefix = '$normalizedOld/';
    if (!normalizedPath.startsWith(prefix)) {
      return null;
    }
    return '$normalizedNew/${normalizedPath.substring(prefix.length)}';
  }
}
