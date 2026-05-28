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
        resolveWorkbenchDropOverlayRect(
          zone: WorkbenchDropZone.left,
          paneSize: size,
        ),
        const Rect.fromLTWH(0, 0, 100, 160),
      );
      expect(
        resolveWorkbenchDropOverlayRect(
          zone: WorkbenchDropZone.right,
          paneSize: size,
        ),
        const Rect.fromLTWH(100, 0, 100, 160),
      );
      expect(
        resolveWorkbenchDropOverlayRect(
          zone: WorkbenchDropZone.up,
          paneSize: size,
        ),
        const Rect.fromLTWH(0, 0, 200, 80),
      );
      expect(
        resolveWorkbenchDropOverlayRect(
          zone: WorkbenchDropZone.down,
          paneSize: size,
        ),
        const Rect.fromLTWH(0, 80, 200, 80),
      );
      expect(
        resolveWorkbenchDropOverlayRect(
          zone: WorkbenchDropZone.center,
          paneSize: size,
        ),
        const Rect.fromLTWH(52, 32, 96, 96),
      );
    });

    test(
      'split direction helpers cover center fill, repaint, and flex clamping',
      () {
        expect(
          splitDirectionFillRectForTesting(
            WorkbenchDropZone.center,
            const Size(200, 160),
          ),
          Rect.zero,
        );
        expect(
          splitDirectionPainterShouldRepaintForTesting(
            WorkbenchDropZone.left,
            WorkbenchDropZone.left,
          ),
          isFalse,
        );
        expect(
          splitDirectionPainterShouldRepaintForTesting(
            WorkbenchDropZone.left,
            WorkbenchDropZone.right,
          ),
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
                axis: WorkbenchSplitAxis.vertical,
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
          zone: WorkbenchDropZone.center,
        ),
        isTrue,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 1,
          zone: WorkbenchDropZone.center,
        ),
        isFalse,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 2,
          zone: WorkbenchDropZone.right,
        ),
        isTrue,
      );
    });
  });
}
