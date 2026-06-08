import 'dart:io' show Directory, File, FileSystemException, Link;

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_uri_policy.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_viewer_images.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_viewer_surface.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markdown viewer link policy only accepts web URLs with hosts', () {
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('https://example.com/docs')),
      isTrue,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('http://example.com')),
      isTrue,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('file:///tmp/readme.md')),
      isFalse,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('mailto:test@example.com')),
      isFalse,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('vscode://file/foo')),
      isFalse,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.parse('https:///missing-host')),
      isFalse,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.tryParse('docs/readme.md')),
      isFalse,
    );
    expect(
      isSupportedMarkdownViewerLinkUri(Uri.tryParse('not a uri')),
      isFalse,
    );
  });

  test('markdown viewer image policy resolves only safe image sources', () {
    expect(
      isSupportedMarkdownViewerRemoteImageUri(
        Uri.parse('https://example.com/diagram.png'),
      ),
      isTrue,
    );
    expect(
      isSupportedMarkdownViewerRemoteImageUri(
        Uri.parse('http://example.com/diagram.png'),
      ),
      isTrue,
    );
    expect(
      isSupportedMarkdownViewerRemoteImageUri(
        Uri.parse('file:///tmp/diagram.png'),
      ),
      isFalse,
    );
    expect(
      resolveWorkspaceMarkdownImagePath(
        markdownPath: 'docs/readme.md',
        rawImageUrl: './images/diagram.png',
      ),
      'docs/images/diagram.png',
    );
    expect(
      resolveWorkspaceMarkdownImagePath(
        markdownPath: 'docs/guides/readme.md',
        rawImageUrl: '../assets/diagram.png',
      ),
      'docs/assets/diagram.png',
    );
    expect(
      resolveWorkspaceMarkdownImagePath(
        markdownPath: 'docs/readme.md',
        rawImageUrl: '../../secret.png',
      ),
      isNull,
    );
    expect(
      resolveWorkspaceMarkdownImagePath(
        markdownPath: 'docs/readme.md',
        rawImageUrl: r'C:\secret.png',
      ),
      isNull,
    );
    expect(
      resolveWorkspaceMarkdownImagePath(
        markdownPath: 'docs/readme.md',
        rawImageUrl: 'file:///tmp/secret.png',
      ),
      isNull,
    );
  });

  test('markdown viewer image builder creates explicit non-local widgets', () {
    final remoteImage =
        buildMarkdownViewerImage(
              workspacePath: '/repo/alera',
              markdownPath: 'docs/readme.md',
              imageUrl: 'https://example.com/diagram.png',
            )
            as Image;
    expect(remoteImage.image, isA<NetworkImage>());
    expect(
      (remoteImage.image as NetworkImage).url,
      'https://example.com/diagram.png',
    );

    final blockedImage = buildMarkdownViewerImage(
      workspacePath: '/repo/alera',
      markdownPath: 'docs/readme.md',
      imageUrl: 'file:///tmp/secret.png',
    );
    expect(blockedImage, isNot(isA<Image>()));
  });

  test('markdown viewer dirty content guard skips unchanged previews', () {
    expect(
      shouldUpdateMarkdownViewerDirtyContent(
        currentContent: '# Dirty',
        dirtyEditorContent: '# Dirty',
        loading: false,
        loadError: null,
        usingDirtyEditorContent: true,
      ),
      isFalse,
    );
    expect(
      shouldUpdateMarkdownViewerDirtyContent(
        currentContent: '# Dirty',
        dirtyEditorContent: '# Changed',
        loading: false,
        loadError: null,
        usingDirtyEditorContent: true,
      ),
      isTrue,
    );
    expect(
      shouldUpdateMarkdownViewerDirtyContent(
        currentContent: '# Dirty',
        dirtyEditorContent: '# Dirty',
        loading: true,
        loadError: null,
        usingDirtyEditorContent: true,
      ),
      isTrue,
    );
    expect(
      shouldUpdateMarkdownViewerDirtyContent(
        currentContent: '# Dirty',
        dirtyEditorContent: '# Dirty',
        loading: false,
        loadError: StateError('failed'),
        usingDirtyEditorContent: true,
      ),
      isTrue,
    );
    expect(
      shouldUpdateMarkdownViewerDirtyContent(
        currentContent: '# Dirty',
        dirtyEditorContent: '# Dirty',
        loading: false,
        loadError: null,
        usingDirtyEditorContent: false,
      ),
      isTrue,
    );
  });

  test('canonical local image resolver allows workspace files', () async {
    final tempRoot = await Directory.systemTemp.createTemp('alera-md-image-');
    addTearDown(() async {
      await tempRoot.delete(recursive: true);
    });
    final workspace = await Directory('${tempRoot.path}/workspace').create();
    final image = await File(
      '${workspace.path}/docs/images/diagram.png',
    ).create(recursive: true);
    await image.writeAsBytes(const <int>[0]);

    final resolved = await resolveWorkspaceMarkdownImageFilePath(
      workspacePath: workspace.path,
      markdownPath: 'docs/readme.md',
      rawImageUrl: './images/diagram.png',
    );

    expect(resolved, await image.resolveSymbolicLinks());
  });

  test('canonical local image resolver constrains symlink targets', () async {
    final tempRoot = await Directory.systemTemp.createTemp('alera-md-symlink-');
    addTearDown(() async {
      await tempRoot.delete(recursive: true);
    });
    final workspace = await Directory('${tempRoot.path}/workspace').create();
    final docs = await Directory('${workspace.path}/docs').create();
    final assets = await Directory('${workspace.path}/assets').create();
    final outside = await Directory('${tempRoot.path}/outside').create();
    final insideImage = await File('${assets.path}/inside.png').create();
    final outsideImage = await File('${outside.path}/outside.png').create();
    await insideImage.writeAsBytes(const <int>[1]);
    await outsideImage.writeAsBytes(const <int>[2]);

    final symlinksCreated =
        await _createSymlinkOrSkip(
          linkPath: '${docs.path}/inside-link.png',
          targetPath: insideImage.path,
        ) &&
        await _createSymlinkOrSkip(
          linkPath: '${docs.path}/outside-link.png',
          targetPath: outsideImage.path,
        ) &&
        await _createSymlinkOrSkip(
          linkPath: '${docs.path}/broken-link.png',
          targetPath: '${outside.path}/missing.png',
        );
    if (!symlinksCreated) {
      return;
    }

    expect(
      await resolveWorkspaceMarkdownImageFilePath(
        workspacePath: workspace.path,
        markdownPath: 'docs/readme.md',
        rawImageUrl: './inside-link.png',
      ),
      await insideImage.resolveSymbolicLinks(),
    );
    expect(
      await resolveWorkspaceMarkdownImageFilePath(
        workspacePath: workspace.path,
        markdownPath: 'docs/readme.md',
        rawImageUrl: './outside-link.png',
      ),
      isNull,
    );
    expect(
      await resolveWorkspaceMarkdownImageFilePath(
        workspacePath: workspace.path,
        markdownPath: 'docs/readme.md',
        rawImageUrl: './broken-link.png',
      ),
      isNull,
    );
  });

  testWidgets('renders dirty editor content instead of saved disk content', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService('# Disk');
    registry.documentFor('editor-tab')
      ..attachFile(workspacePath: '/repo/alera', relativePath: 'docs/readme.md')
      ..acceptLoaded(
        _editorFile(rawContent: '# Disk', displayContent: '# Disk'),
      )
      ..updateCurrentText('# Dirty');

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Dirty'), findsOneWidget);
    expect(find.textContaining('Disk'), findsNothing);
    expect(service.reads, isEmpty);
  });

  testWidgets('reads disk content when a matching editor buffer is clean', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService('# Disk');
    registry.documentFor('editor-tab')
      ..attachFile(workspacePath: '/repo/alera', relativePath: 'docs/readme.md')
      ..acceptLoaded(
        _editorFile(rawContent: '# Cached', displayContent: '# Cached'),
      );

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Disk'), findsOneWidget);
    expect(find.textContaining('Cached'), findsNothing);
    expect(service.reads, const <String>['docs/readme.md']);
  });

  testWidgets('falls back to disk content when no editor buffer exists', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService('# Disk');

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Disk'), findsOneWidget);
    expect(service.reads, const <String>['docs/readme.md']);
  });

  testWidgets('refresh reloads disk content while the editor buffer is clean', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService('# Disk v1');
    registry.documentFor('editor-tab')
      ..attachFile(workspacePath: '/repo/alera', relativePath: 'docs/readme.md')
      ..acceptLoaded(
        _editorFile(rawContent: '# Disk v1', displayContent: '# Disk v1'),
      );

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Disk v1'), findsOneWidget);

    service.content = '# Disk v2';
    await tester.tap(find.byTooltip('Refresh preview'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Disk v2'), findsOneWidget);
    expect(find.textContaining('Disk v1'), findsNothing);
    expect(service.reads, const <String>['docs/readme.md', 'docs/readme.md']);
  });

  testWidgets('updates an open preview when editor content changes', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService('# Disk');

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Disk'), findsOneWidget);

    registry.documentFor('editor-tab')
      ..attachFile(workspacePath: '/repo/alera', relativePath: 'docs/readme.md')
      ..acceptLoaded(
        _editorFile(rawContent: '# Disk', displayContent: '# Disk'),
      )
      ..updateCurrentText('# Dirty');
    await tester.pumpAndSettle();

    expect(find.textContaining('Dirty'), findsOneWidget);
    expect(find.textContaining('Disk'), findsNothing);
    expect(service.reads, const <String>['docs/readme.md']);
  });

  testWidgets('ignores dirty editor changes from unrelated files', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService('# Disk');
    registry.documentFor('editor-tab')
      ..attachFile(workspacePath: '/repo/alera', relativePath: 'docs/readme.md')
      ..acceptLoaded(
        _editorFile(rawContent: '# Disk', displayContent: '# Disk'),
      )
      ..updateCurrentText('# Dirty preview');

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await tester.pumpAndSettle();

    registry.documentFor('other-editor-tab')
      ..attachFile(workspacePath: '/repo/alera', relativePath: 'docs/other.md')
      ..acceptLoaded(
        _editorFile(rawContent: '# Other', displayContent: '# Other'),
      )
      ..updateCurrentText('# Other dirty');
    await tester.pumpAndSettle();

    expect(find.textContaining('Dirty preview'), findsOneWidget);
    expect(find.textContaining('Other dirty'), findsNothing);
    expect(service.reads, isEmpty);
  });

  testWidgets('does not launch non-web markdown links', (tester) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService(
      '[Local file](file:///tmp/readme.md)',
    );
    final launcher = _FakeExternalUriLauncher();

    await tester.pumpWidget(
      _surface(
        registry: registry,
        workspaceFiles: service,
        externalUriLauncher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Local file'));
    await tester.pumpAndSettle();

    expect(launcher.opened, isEmpty);
  });

  testWidgets('blocks unsupported markdown image sources in the preview', (
    tester,
  ) async {
    final registry = EditorSessionRegistry();
    final service = _FakeWorkspaceFileService(
      '![32x16](file:///tmp/secret.png)',
    );

    await tester.pumpWidget(
      _surface(registry: registry, workspaceFiles: service),
    );
    await _pumpLoadedMarkdown(tester);

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(AleraIcons.imageError), findsOneWidget);
  });
}

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
      editorSessionRegistryProvider.overrideWithValue(registry),
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

Workspace _workspace({String path = '/repo/alera'}) {
  final now = DateTime(2026);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'alera',
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab() {
  final now = DateTime(2026);
  return WorkspaceTabRecord(
    id: 'preview-tab',
    workspaceId: 'workspace-1',
    kind: WorkspaceTabKind.markdownViewer,
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
    size: BigInt.from(rawContent.length),
  );
}

class _FakeWorkspaceFileService extends WorkspaceFileService {
  _FakeWorkspaceFileService(this.content);

  String content;
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
      size: BigInt.from(content.length),
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
