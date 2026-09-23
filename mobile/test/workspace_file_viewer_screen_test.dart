import 'dart:convert';

import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_markdown_image_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_markdown_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/fake_workspace_files_client.dart';

void main() {
  const markdown = '# Project Title\n\nSome **bold** text.';

  FakeTerminalClient fakeClient(Map<String, FakeWorkspaceFile> files) {
    return FakeTerminalClient()..workspaceFileContents = files;
  }

  Future<FakeTerminalClient> pumpViewer(
    WidgetTester tester, {
    required String relativePath,
    String content = markdown,
    int? highlightLine,
    Future<bool> Function(Uri url)? openExternalUrl,
  }) async {
    final client = fakeClient(<String, FakeWorkspaceFile>{
      relativePath: (mimeType: 'text/markdown', bytes: utf8.encode(content)),
    });
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          home: WorkspaceFileViewerScreen(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
            relativePath: relativePath,
            highlightLine: highlightLine,
            openExternalUrl: openExternalUrl ?? (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('Markdown opens as a rendered preview with a source toggle', (
    tester,
  ) async {
    await pumpViewer(tester, relativePath: 'docs/readme.md');

    expect(find.byType(AleraMarkdownView), findsOneWidget);
    expect(
      find.textContaining('Project Title', findRichText: true),
      findsWidgets,
    );
    expect(find.text('1  # Project Title'), findsNothing);

    await tester.tap(find.byTooltip('Show Source'));
    await tester.pumpAndSettle();
    expect(find.byType(AleraMarkdownView), findsNothing);
    expect(find.text('1  # Project Title'), findsOneWidget);

    await tester.tap(find.byTooltip('Show Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(AleraMarkdownView), findsOneWidget);
  });

  testWidgets('a search match opens Markdown source at its line', (
    tester,
  ) async {
    await pumpViewer(tester, relativePath: 'docs/guide.mdx', highlightLine: 3);

    expect(find.byType(AleraMarkdownView), findsNothing);
    expect(find.text('3  Some **bold** text.'), findsOneWidget);
    expect(find.byTooltip('Show Preview'), findsOneWidget);
  });

  testWidgets('non-Markdown files keep the source view without a toggle', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      relativePath: 'lib/main.dart',
      content: 'void main() {}',
    );

    expect(find.text('1  void main() {}'), findsOneWidget);
    expect(find.byTooltip('Show Preview'), findsNothing);
    expect(find.byTooltip('Show Source'), findsNothing);
  });

  testWidgets('only web links reach the browser', (tester) async {
    final opened = <Uri>[];
    await pumpViewer(
      tester,
      relativePath: 'readme.md',
      openExternalUrl: (url) async {
        opened.add(url);
        return true;
      },
    );
    final view = tester.widget<AleraMarkdownView>(
      find.byType(AleraMarkdownView),
    );

    view.onLinkTap('javascript:alert(1)');
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Link cannot be opened'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(AleraMarkdownView)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    view.onLinkTap('https://example.com/docs');
    await tester.pumpAndSettle();
    expect(opened, <Uri>[Uri.parse('https://example.com/docs')]);
    expect(find.text('Link cannot be opened'), findsNothing);
  });

  testWidgets('a link the browser refuses reports that it cannot be opened', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      relativePath: 'readme.md',
      openExternalUrl: (_) async => false,
    );

    tester
        .widget<AleraMarkdownView>(find.byType(AleraMarkdownView))
        .onLinkTap('https://example.com');
    await tester.pumpAndSettle();
    expect(find.text('Link cannot be opened'), findsOneWidget);
  });

  group('Markdown images', () {
    Future<FakeTerminalClient> pumpImage(
      WidgetTester tester, {
      required String imageUrl,
      Map<String, FakeWorkspaceFile> files =
          const <String, FakeWorkspaceFile>{},
    }) async {
      final client = fakeClient(files);
      addTearDown(client.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceClientProvider('host-1')
                .overrideWith((ref) async => client),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WorkspaceMarkdownImage(
                hostId: 'host-1',
                workspaceId: 'workspace-1',
                markdownPath: 'docs/readme.md',
                imageUrl: imageUrl,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return client;
    }

    testWidgets('relative images load through the workspace read', (
      tester,
    ) async {
      final client = await pumpImage(
        tester,
        imageUrl: './img.png',
        files: <String, FakeWorkspaceFile>{
          'docs/img.png': (mimeType: 'image/png', bytes: <int>[1, 2, 3]),
        },
      );

      expect(
        client.calls,
        contains('readWorkspaceFile workspace-1 docs/img.png 0'),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
    });

    testWidgets('images escaping the workspace are never read', (tester) async {
      final client = await pumpImage(tester, imageUrl: '../../secret.png');

      expect(
        client.calls.where((call) => call.startsWith('readWorkspaceFile')),
        isEmpty,
      );
      expect(find.byIcon(AleraIcons.imageError), findsOneWidget);
    });

    testWidgets('non-image files render the placeholder', (tester) async {
      await pumpImage(
        tester,
        imageUrl: 'notes.png',
        files: <String, FakeWorkspaceFile>{
          'docs/notes.png': (mimeType: 'text/plain', bytes: utf8.encode('hi')),
        },
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(AleraIcons.imageError), findsOneWidget);
    });

    Future<Object?> readImage(
      Map<String, FakeWorkspaceFile> files,
      String relativePath,
    ) async {
      final client = fakeClient(files);
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      final provider = workspaceMarkdownImageProvider(
        'host-1',
        'workspace-1',
        relativePath,
      );
      container.listen(provider, (_, _) {});
      return container.read(provider.future);
    }

    test('large images are assembled from several ranges', () async {
      final bytes = List<int>.generate(
        maxMobileWorkspaceFileRangeBytes + 10,
        (index) => index % 256,
      );
      final image = await readImage(<String, FakeWorkspaceFile>{
        'big.png': (mimeType: 'image/png', bytes: bytes),
      }, 'big.png');

      expect(image, bytes);
    });

    test('images above the size cap are not loaded', () async {
      final image = await readImage(<String, FakeWorkspaceFile>{
        'huge.png': (
          mimeType: 'image/png',
          bytes: List<int>.filled(maxMobileMarkdownImageBytes + 1, 0),
        ),
      }, 'huge.png');

      expect(image, isNull);
    });

    test('a missing image resolves to null instead of failing', () async {
      final image = await readImage(
        const <String, FakeWorkspaceFile>{},
        'missing.png',
      );

      expect(image, isNull);
    });
  });
}
