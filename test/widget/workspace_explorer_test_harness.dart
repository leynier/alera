part of 'workspace_explorer_test.dart';

Future<void> _pumpExplorer(
  WidgetTester tester,
  _FakeWorkspaceFileService service, {
  ValueChanged<String>? onOpenFile,
  ValueChanged<String>? onOpenFilePermanently,
  EditorSessionRegistry? registry,
  WorkspaceFolderOpener? folderOpener,
  GitBackend? gitBackend,
  String? focusedSourceControlRoot,
  Future<bool> Function(String relativePath)? onFocusSourceControlFolder,
  VoidCallback? onClearSourceControlRoot,
}) async {
  await tester.pumpWidget(
    _withWorkspaceFiles(
      service,
      registry: registry,
      folderOpener: folderOpener,
      gitBackend: gitBackend,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 480,
            child: WorkspaceExplorer(
              workspace: _workspace(),
              mode: .hideIgnored,
              onModeChanged: (_) {},
              onOpenFile: onOpenFile ?? (_) {},
              onOpenFilePermanently: onOpenFilePermanently,
              focusedSourceControlRoot: focusedSourceControlRoot,
              onFocusSourceControlFolder: onFocusSourceControlFolder,
              onClearSourceControlRoot: onClearSourceControlRoot,
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class const _ExplorerVisibilityHarness({
  super.key,
  required final Workspace workspace,
}) extends StatefulWidget {
  @override
  State<_ExplorerVisibilityHarness> createState() =>
      _ExplorerVisibilityHarnessState();
}

class _ExplorerVisibilityHarnessState
    extends State<_ExplorerVisibilityHarness> {
  bool _visible = true;

  void hideExplorer() => setState(() => _visible = false);

  void showExplorer() => setState(() => _visible = true);

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return WorkspaceExplorer(
      workspace: widget.workspace,
      mode: .hideIgnored,
      onModeChanged: (_) {},
      onOpenFile: (_) {},
      onPathMoved: (_, _) async {},
    );
  }
}

class const _WorkspaceExplorerModeHarness() extends StatefulWidget {
  @override
  State<_WorkspaceExplorerModeHarness> createState() =>
      _WorkspaceExplorerModeHarnessState();
}

class _WorkspaceExplorerModeHarnessState
    extends State<_WorkspaceExplorerModeHarness> {
  WorkspaceExplorerMode _mode = .hideIgnored;

  @override
  Widget build(BuildContext context) {
    return WorkspaceExplorer(
      workspace: _workspace(),
      mode: _mode,
      onModeChanged: (mode) => setState(() => _mode = mode),
      onOpenFile: (_) {},
      onPathMoved: (_, _) async {},
    );
  }
}

Widget _withWorkspaceFiles(
  _FakeWorkspaceFileService service, {
  required Widget child,
  EditorSessionRegistry? registry,
  WorkspaceFolderOpener? folderOpener,
  GitBackend? gitBackend,
}) {
  return ProviderScope(
    overrides: [
      workspaceFileServiceProvider.overrideWithValue(service),
      gitBackendProvider.overrideWithValue(gitBackend ?? FakeGitBackend()),
      if (folderOpener != null)
        workspaceFolderOpenerProvider.overrideWithValue(folderOpener),
      if (registry != null)
        editorSessionRegistryProvider.overrideWithValue(registry),
    ],
    child: child,
  );
}

Widget _workspaceContextSidebar(Workspace workspace) {
  return WorkspaceContextSidebar(
    workspace: workspace,
    prefs: .defaults,
    onToggleVisible: () {},
    onResize: (_) {},
    onSetContextPanelTab: (_) {},
    onSetExplorerMode: (_) {},
    onSetGitDiffViewMode: (_) {},
    onSetGitDiffGroupMode: (_) {},
    onOpenFile: (_) {},
    onOpenGitDiff: ({
      relativePath,
      area,
      gitDiffRoot,
      required scope,
      bool preview = false,
    }) async {},
    onOpenGitCommitDiff: ({
      relativePath,
      oldPath,
      required scope,
      gitDiffRoot,
      required commitOid,
      parentOid,
      required compareRef,
      subject,
      message,
      bool preview = false,
    }) async {},
    onOpenSearchMatch: (_) {},
    onPathMoved: (_, _) async {},
  );
}
