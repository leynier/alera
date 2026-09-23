part of 'workspace_markdown_viewer_surface_test.dart';

Future<void> _pumpLoadedMarkdown(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Future<bool> _createSymlinkOrSkip({
  required String linkPath,
  required String targetPath,
}) async {
  try {
    await Link(linkPath).create(targetPath);
    return true;
  } on FileSystemException catch (error) {
    markTestSkipped('Symlink creation failed: $error');
    return false;
  }
}

Widget _surface({
  required EditorSessionRegistry registry,
  required WorkspaceFileService workspaceFiles,
  ExternalUriLauncher? externalUriLauncher,
  Workspace? workspace,
}) {
  return ProviderScope(
    overrides: [
      // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
      workbenchControllerProvider.overrideWith(_PreviewWorkbenchController.new),
      // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
      editorSessionRegistryProvider.overrideWithValue(registry),
      // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
      workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
      if (externalUriLauncher != null)
        externalUriLauncherProvider.overrideWithValue(externalUriLauncher),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: WorkspaceMarkdownViewerSurface(
          workspace: workspace ?? _workspace(),
          tab: _tab(),
          onOpenEditorTab: (_) {},
        ),
      ),
    ),
  );
}

class _PreviewWorkbenchController extends WorkbenchController {
  @override
  WorkbenchState build() => WorkbenchState(
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      'workspace-1': <WorkspaceTabRecord>[
        _tab().copyWith(id: 'editor-tab'),
        _tab().copyWith(id: 'other-editor-tab'),
      ],
    },
  );
}

Workspace _workspace({String path = '/repo/alera'}) {
  final now = DateTime(2026);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'alera',
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
}

WorkspaceTabRecord _tab() {
  final now = DateTime(2026);
  return WorkspaceTabRecord(
    id: 'preview-tab',
    workspaceId: 'workspace-1',
    kind: .markdownViewer,
    title: 'readme.md preview',
    createdAt: now,
    updatedAt: now,
    payload: const <String, Object?>{
      workspaceTabFilePathPayloadKey: 'docs/readme.md',
    },
  );
}

native.WorkspaceEditorTextFile _editorFile({
  required String rawContent,
  required String displayContent,
}) {
  return native.WorkspaceEditorTextFile(
    rawContent: rawContent,
    displayContent: displayContent,
    contentToken: 'editor-token',
    modifiedMillis: 0,
    size: .from(rawContent.length),
  );
}

class _FakeWorkspaceFileService(var String content)
    extends WorkspaceFileService {
  final List<String> reads = <String>[];

  @override
  Future<native.WorkspaceTextFile> readTextFile({
    required String workspacePath,
    required String relativePath,
  }) async {
    reads.add(relativePath);
    return native.WorkspaceTextFile(
      content: content,
      contentToken: 'disk-token',
      modifiedMillis: 0,
      size: .from(content.length),
    );
  }
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    opened.add(uri);
  }
}
