import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  group('WorkspaceWorkbenchView', () {
    late _FakeTerminalRuntime terminalRuntime;
    late List<String?> createdTabs;
    late List<_SelectedTabAction> selectedTabs;
    late List<String> closedTabs;
    late List<List<String>> closedTabGroups;
    late List<String> renamedTabs;
    late List<_MovedTabAction> movedTabs;
    late List<_SplitGroupAction> splitGroups;
    late List<String> mergedGroups;
    late List<_UpdatedSplitRatioAction> updatedRatios;

    setUp(() {
      terminalRuntime = _FakeTerminalRuntime();
      createdTabs = <String?>[];
      selectedTabs = <_SelectedTabAction>[];
      closedTabs = <String>[];
      closedTabGroups = <List<String>>[];
      renamedTabs = <String>[];
      movedTabs = <_MovedTabAction>[];
      splitGroups = <_SplitGroupAction>[];
      mergedGroups = <String>[];
      updatedRatios = <_UpdatedSplitRatioAction>[];
    });

    testWidgets('falls back to a single layout when none is provided', (
      tester,
    ) async {
      final tab = _tab('tab-1', title: 'Terminal 1');

      await _pumpWorkbenchView(
        tester,
        tabs: <WorkspaceTabRecord>[tab],
        terminalRuntime: terminalRuntime,
        layout: null,
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      expect(find.text('Terminal 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('terminal-tab-1')),
        findsOneWidget,
      );
      expect(terminalRuntime.requestedTabIds, contains('tab-1'));
    });

    testWidgets('shows a loading state for non-terminal tabs', (tester) async {
      final tab = _tab('tab-1', title: 'Editor', kind: WorkspaceTabKind.editor);

      await _pumpWorkbenchView(
        tester,
        tabs: <WorkspaceTabRecord>[tab],
        terminalRuntime: terminalRuntime,
        layout: WorkbenchLayout.single(
          workspaceId: _workspaceId,
          tabIds: <String>[tab.id],
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(terminalRuntime.requestedTabIds, isEmpty);
    });

    testWidgets('dragging the split handle updates the split ratio', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: _splitLayout(
          firstTabId: tabs[0].id,
          secondTabId: tabs[1].id,
          axis: WorkbenchSplitAxis.vertical,
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WorkspaceWorkbenchView)),
      );
      await gesture.moveBy(const Offset(48, 0));
      await gesture.up();
      await tester.pump();

      expect(updatedRatios, hasLength(1));
      expect(updatedRatios.single.nodePath, const <int>[]);
      expect(updatedRatios.single.ratio, isA<double>());
    });

    testWidgets('split handles track hover and cancelled drags', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      final handlePoint = tester.getCenter(find.byType(WorkspaceWorkbenchView));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: handlePoint);
      await tester.pump();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();

      final drag = await tester.startGesture(handlePoint);
      await tester.pump();
      await drag.cancel();
      await tester.pump();

      expect(updatedRatios, isEmpty);
    });

    testWidgets('dragging a tab across panes invokes the move callback', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
        size: const Size(620, 320),
      );

      final draggableTabs = find.byWidgetPredicate(
        (widget) => widget is Draggable,
      );
      final dragStart =
          tester.getTopLeft(draggableTabs.at(1)) + const Offset(24, 16);
      final leftPaneRect = tester.getRect(
        find.byKey(const ValueKey<String>('terminal-tab-1')),
      );

      final gesture = await tester.startGesture(dragStart);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(
        Offset(leftPaneRect.left + 8, leftPaneRect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        movedTabs,
        contains(
          const _MovedTabAction('tab-2', 'group-a', WorkbenchDropZone.left),
        ),
      );
    });

    testWidgets('pane actions forward split and merge callbacks', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      await tester.tap(find.byTooltip('Pane actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      expect(splitGroups, <_SplitGroupAction>[
        const _SplitGroupAction('group-a', WorkbenchDropZone.right),
      ]);

      await tester.tap(find.byTooltip('Pane actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close split'));
      await tester.pumpAndSettle();

      expect(mergedGroups, <String>['group-a']);
    });

    testWidgets('pane actions route split down, left, and up', (tester) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      for (final label in <String>['Split down', 'Split left', 'Split up']) {
        await tester.tap(find.byTooltip('Pane actions').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(splitGroups, <_SplitGroupAction>[
        const _SplitGroupAction('group-a', WorkbenchDropZone.down),
        const _SplitGroupAction('group-a', WorkbenchDropZone.left),
        const _SplitGroupAction('group-a', WorkbenchDropZone.up),
      ]);
    });

    testWidgets(
      'new terminal and tab selection callbacks include the group id',
      (tester) async {
        final tabs = <WorkspaceTabRecord>[
          _tab('tab-1', title: 'Terminal 1'),
          _tab('tab-2', title: 'Terminal 2'),
        ];
        final layout = WorkbenchLayout.single(
          workspaceId: _workspaceId,
          groupId: 'group-a',
          tabIds: tabs.map((tab) => tab.id).toList(),
        );

        await _pumpWorkbenchView(
          tester,
          tabs: tabs,
          terminalRuntime: terminalRuntime,
          layout: layout,
          createdTabs: createdTabs,
          selectedTabs: selectedTabs,
          closedTabs: closedTabs,
          closedTabGroups: closedTabGroups,
          renamedTabs: renamedTabs,
          movedTabs: movedTabs,
          splitGroups: splitGroups,
          mergedGroups: mergedGroups,
          updatedRatios: updatedRatios,
        );

        await tester.tap(find.byTooltip('New terminal'));
        await tester.pump();
        await tester.tap(find.text('Terminal 1'));
        await tester.pump();

        expect(createdTabs, <String?>['group-a']);
        expect(selectedTabs, <_SelectedTabAction>[
          const _SelectedTabAction('group-a', 'tab-1'),
        ]);
      },
    );

    testWidgets('tab context menu closes sibling tabs', (tester) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
        _tab('tab-3', title: 'Terminal 3'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: WorkbenchLayout.single(
          workspaceId: _workspaceId,
          groupId: 'group-a',
          tabIds: tabs.map((tab) => tab.id).toList(),
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text('Close others'));
      await tester.pumpAndSettle();

      expect(closedTabGroups, <List<String>>[
        <String>['tab-1', 'tab-3'],
      ]);

      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text('Close tabs to the right'));
      await tester.pumpAndSettle();

      expect(closedTabGroups, <List<String>>[
        <String>['tab-1', 'tab-3'],
        <String>['tab-3'],
      ]);
    });

    testWidgets('tab context menu renames and splits the active group', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: WorkbenchLayout.single(
          workspaceId: _workspaceId,
          groupId: 'group-a',
          tabIds: tabs.map((tab) => tab.id).toList(),
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text('Change title'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Renamed terminal');
      await tester.tap(find.text('Change title').last);
      await tester.pumpAndSettle();

      expect(renamedTabs, <String>['Renamed terminal']);

      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();

      expect(
        splitGroups,
        contains(const _SplitGroupAction('group-a', WorkbenchDropZone.right)),
      );
    });

    testWidgets('tab context menu routes split up, down, left, and close', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: WorkbenchLayout.single(
          workspaceId: _workspaceId,
          groupId: 'group-a',
          tabIds: tabs.map((tab) => tab.id).toList(),
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      for (final label in <String>['Split up', 'Split down', 'Split left']) {
        await _openTabContextMenu(tester, 'Terminal 2');
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        splitGroups,
        containsAll(<_SplitGroupAction>[
          const _SplitGroupAction('group-a', WorkbenchDropZone.up),
          const _SplitGroupAction('group-a', WorkbenchDropZone.down),
          const _SplitGroupAction('group-a', WorkbenchDropZone.left),
        ]),
      );
      expect(closedTabs, <String>['tab-2']);
    });

    testWidgets('active-tab fallback picks the first available tab', (
      tester,
    ) async {
      final tabs = <WorkspaceTabRecord>[
        _tab('tab-1', title: 'Terminal 1'),
        _tab('tab-2', title: 'Terminal 2'),
      ];

      await _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: WorkbenchLayout(
          workspaceId: _workspaceId,
          root: WorkbenchLayoutNode.leaf('group-a'),
          groups: <String, WorkbenchPaneGroup>{
            'group-a': WorkbenchPaneGroup(
              id: 'group-a',
              tabIds: tabs.map((tab) => tab.id).toList(),
              activeTabId: 'missing-tab',
            ),
          },
          activeGroupId: 'group-a',
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      expect(
        find.byKey(const ValueKey<String>('terminal-tab-1')),
        findsOneWidget,
      );
      expect(terminalRuntime.requestedTabIds, contains('tab-1'));
    });

    testWidgets('browser tabs use the browser icon in the chip', (
      tester,
    ) async {
      final tab = _tab(
        'tab-1',
        title: 'Browser',
        kind: WorkspaceTabKind.browser,
      );

      await _pumpWorkbenchView(
        tester,
        tabs: <WorkspaceTabRecord>[tab],
        terminalRuntime: terminalRuntime,
        layout: WorkbenchLayout.single(
          workspaceId: _workspaceId,
          tabIds: <String>[tab.id],
        ),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
      );

      expect(find.byIcon(Icons.public), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

const String _workspaceId = 'workspace-1';

Future<void> _pumpWorkbenchView(
  WidgetTester tester, {
  required List<WorkspaceTabRecord> tabs,
  required WorkbenchLayout? layout,
  required _FakeTerminalRuntime terminalRuntime,
  required List<String?> createdTabs,
  required List<_SelectedTabAction> selectedTabs,
  required List<String> closedTabs,
  required List<List<String>> closedTabGroups,
  required List<String> renamedTabs,
  required List<_MovedTabAction> movedTabs,
  required List<_SplitGroupAction> splitGroups,
  required List<String> mergedGroups,
  required List<_UpdatedSplitRatioAction> updatedRatios,
  Size size = const Size(420, 280),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: WorkspaceWorkbenchView(
              project: _project(),
              workspace: _workspace(),
              tabs: tabs,
              layout: layout,
              terminalRuntime: terminalRuntime,
              onCreateTab: ({String? targetGroupId}) async {
                createdTabs.add(targetGroupId);
              },
              onSelectTab: ({required String groupId, required String tabId}) {
                selectedTabs.add(_SelectedTabAction(groupId, tabId));
              },
              onCloseTab: closedTabs.add,
              onCloseTabs: (tabIds) => closedTabGroups.add(tabIds),
              onRenameTab:
                  ({required String tabId, required String title}) async {
                    renamedTabs.add(title);
                  },
              onMoveTab:
                  ({
                    required String tabId,
                    required String targetGroupId,
                    required WorkbenchDropZone zone,
                  }) async {
                    movedTabs.add(_MovedTabAction(tabId, targetGroupId, zone));
                  },
              onSplitGroup:
                  ({
                    required String groupId,
                    required WorkbenchDropZone zone,
                  }) async {
                    splitGroups.add(_SplitGroupAction(groupId, zone));
                  },
              onMergeGroup: ({required String groupId}) async {
                mergedGroups.add(groupId);
              },
              onUpdateSplitRatio:
                  ({required List<int> nodePath, required double ratio}) {
                    updatedRatios.add(
                      _UpdatedSplitRatioAction(nodePath, ratio),
                    );
                  },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openTabContextMenu(WidgetTester tester, String title) async {
  await tester.tapAt(
    tester.getCenter(find.text(title).first),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

Project _project() => Project(
  id: 'project-1',
  name: 'Alera',
  repoPath: '/tmp/alera',
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
);

Workspace _workspace() => Workspace(
  id: _workspaceId,
  projectId: 'project-1',
  name: 'Main',
  branch: 'main',
  path: '/tmp/alera',
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

WorkspaceTabRecord _tab(
  String id, {
  required String title,
  WorkspaceTabKind kind = WorkspaceTabKind.terminal,
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: _workspaceId,
    title: title,
    kind: kind,
    createdAt: DateTime.utc(2026, 5, 22),
    updatedAt: DateTime.utc(2026, 5, 22),
  );
}

WorkbenchLayout _splitLayout({
  required String firstTabId,
  required String secondTabId,
  WorkbenchSplitAxis axis = WorkbenchSplitAxis.horizontal,
}) {
  return WorkbenchLayout(
    workspaceId: _workspaceId,
    root: WorkbenchLayoutNode.split(
      axis: axis,
      first: WorkbenchLayoutNode.leaf('group-a'),
      second: WorkbenchLayoutNode.leaf('group-b'),
      ratio: 0.5,
    ),
    groups: <String, WorkbenchPaneGroup>{
      'group-a': WorkbenchPaneGroup(
        id: 'group-a',
        tabIds: <String>[firstTabId],
        activeTabId: firstTabId,
      ),
      'group-b': WorkbenchPaneGroup(
        id: 'group-b',
        tabIds: <String>[secondTabId],
        activeTabId: secondTabId,
      ),
    },
    activeGroupId: 'group-a',
  );
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final List<String> requestedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits =>
      const Stream<TerminalRuntimeExitEvent>.empty();

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    requestedTabIds.add(tab.id);
    return _sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(
        tabId: tab.id,
        workspaceId: workspace.id,
        displayTitle: tab.title,
      ),
    );
  }

  @override
  void closeTab(String tabId) {}

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {}
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({
    required this.tabId,
    required this.workspaceId,
    required String displayTitle,
  }) : _displayTitle = displayTitle;

  @override
  final String tabId;

  @override
  final String workspaceId;

  final String _displayTitle;

  @override
  String get displayTitle => _displayTitle;

  @override
  bool get isRunning => true;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> restart() async {}

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {}
}

class _SelectedTabAction {
  const _SelectedTabAction(this.groupId, this.tabId);

  final String groupId;
  final String tabId;

  @override
  bool operator ==(Object other) {
    return other is _SelectedTabAction &&
        other.groupId == groupId &&
        other.tabId == tabId;
  }

  @override
  int get hashCode => Object.hash(groupId, tabId);
}

class _MovedTabAction {
  const _MovedTabAction(this.tabId, this.targetGroupId, this.zone);

  final String tabId;
  final String targetGroupId;
  final WorkbenchDropZone zone;

  @override
  bool operator ==(Object other) {
    return other is _MovedTabAction &&
        other.tabId == tabId &&
        other.targetGroupId == targetGroupId &&
        other.zone == zone;
  }

  @override
  int get hashCode => Object.hash(tabId, targetGroupId, zone);
}

class _SplitGroupAction {
  const _SplitGroupAction(this.groupId, this.zone);

  final String groupId;
  final WorkbenchDropZone zone;

  @override
  bool operator ==(Object other) {
    return other is _SplitGroupAction &&
        other.groupId == groupId &&
        other.zone == zone;
  }

  @override
  int get hashCode => Object.hash(groupId, zone);
}

class _UpdatedSplitRatioAction {
  const _UpdatedSplitRatioAction(this.nodePath, this.ratio);

  final List<int> nodePath;
  final double ratio;

  @override
  bool operator ==(Object other) {
    return other is _UpdatedSplitRatioAction &&
        listEquals(other.nodePath, nodePath) &&
        other.ratio == ratio;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(nodePath), ratio);
}
