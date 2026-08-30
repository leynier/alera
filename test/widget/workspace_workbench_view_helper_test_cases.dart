part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewHelperTests() {
  group('workspace workbench view helpers', () {
    test('resolves pane drop zones from size and pointer position', () {
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: const Size(0, 160),
          localPosition: const Offset(0, 0),
        ),
        WorkbenchDropZone.center,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: const Size(200, 160),
          localPosition: const Offset(100, 80),
        ),
        WorkbenchDropZone.center,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: const Size(200, 160),
          localPosition: const Offset(8, 80),
        ),
        WorkbenchDropZone.left,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: const Size(200, 160),
          localPosition: const Offset(192, 80),
        ),
        WorkbenchDropZone.right,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: const Size(200, 160),
          localPosition: const Offset(100, 8),
        ),
        WorkbenchDropZone.up,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: const Size(200, 160),
          localPosition: const Offset(100, 152),
        ),
        WorkbenchDropZone.down,
      );
    });

    test('resolves overlay rectangles for each drop zone', () {
      const size = Size(200, 160);

      expect(
        resolveWorkbenchDropOverlayRect(zone: .left, paneSize: size),
        const Rect.fromLTWH(0, 0, 100, 160),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .right, paneSize: size),
        const Rect.fromLTWH(100, 0, 100, 160),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .up, paneSize: size),
        const Rect.fromLTWH(0, 0, 200, 80),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .down, paneSize: size),
        const Rect.fromLTWH(0, 80, 200, 80),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .center, paneSize: size),
        const Rect.fromLTWH(52, 32, 96, 96),
      );
    });

    test(
      'split direction helpers cover center fill, repaint, and flex clamping',
      () {
        expect(
          splitDirectionFillRectForTesting(.center, const Size(200, 160)),
          Rect.zero,
        );
        expect(
          splitDirectionPainterShouldRepaintForTesting(.left, .left),
          isFalse,
        );
        expect(
          splitDirectionPainterShouldRepaintForTesting(.left, .right),
          isTrue,
        );
        expect(splitRatioFlexForTesting(0), 1);
        expect(splitRatioFlexForTesting(2), 1000);
      },
    );

    testWidgets('fallback split view renders both panes without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              height: 12,
              child: buildSplitViewForAvailableSizeForTesting(
                available: 12,
                axis: .vertical,
                ratio: 0.5,
                first: const SizedBox.expand(
                  child: ColoredBox(color: Colors.red),
                ),
                second: const SizedBox.expand(
                  child: ColoredBox(color: Colors.blue),
                ),
                buildRegularView: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.red,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.blue,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('disables self-center drops for single-tab panes only', () {
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-b',
          targetTabCount: 1,
          zone: .center,
        ),
        isTrue,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 1,
          zone: .center,
        ),
        isFalse,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 2,
          zone: .right,
        ),
        isTrue,
      );
    });

    test('identifies image editor tabs for image preview routing', () {
      final imageTab = _tab(
        'tab-1',
        title: 'logo.png',
        kind: .editor,
        filePath: 'assets/logo.png',
      );
      final textTab = _tab(
        'tab-2',
        title: 'main.dart',
        kind: .editor,
        filePath: 'lib/main.dart',
      );
      final svgTab = _tab(
        'tab-3',
        title: 'icon.svg',
        kind: .editor,
        filePath: 'assets/icon.svg',
      );
      final icoTab = _tab(
        'tab-4',
        title: 'app.ico',
        kind: .editor,
        filePath: 'assets/app.ico',
      );

      expect(workspaceTabUsesImagePreviewForTesting(imageTab), isTrue);
      expect(workspaceTabUsesImagePreviewForTesting(icoTab), isTrue);
      expect(workspaceTabUsesImagePreviewForTesting(textTab), isFalse);
      expect(workspaceTabUsesImagePreviewForTesting(svgTab), isFalse);
    });

    test('identifies only merman preview tabs for merman preview routing', () {
      final editorTab = _tab(
        'tab-1',
        title: 'diagram.mmd',
        kind: .editor,
        filePath: 'docs/diagram.mmd',
      );
      final previewTab = _tab(
        'tab-2',
        title: 'diagram.mmd preview',
        kind: .editor,
        filePath: 'docs/diagram.mmd',
        mermanPreview: true,
      );
      final mermaidTab = _tab(
        'tab-3',
        title: 'diagram.mermaid preview',
        kind: .editor,
        filePath: 'docs/diagram.mermaid',
        mermanPreview: true,
      );

      expect(workspaceTabUsesMermanPreviewForTesting(editorTab), isFalse);
      expect(workspaceTabUsesMermanPreviewForTesting(previewTab), isTrue);
      expect(workspaceTabUsesMermanPreviewForTesting(mermaidTab), isFalse);
    });

    test('identifies PDF tabs for PDF viewer routing', () {
      final pdfTab = _tab(
        'tab-1',
        title: 'guide.pdf',
        kind: .pdf,
        filePath: 'docs/guide.pdf',
      );
      final editorTab = _tab(
        'tab-2',
        title: 'guide.pdf',
        kind: .editor,
        filePath: 'docs/guide.pdf',
      );

      expect(workspaceTabUsesPdfViewerForTesting(pdfTab), isTrue);
      expect(workspaceTabUsesPdfViewerForTesting(editorTab), isFalse);
    });
  });
}
