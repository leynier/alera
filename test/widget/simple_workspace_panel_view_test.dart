import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/workbench/domain/simple_workspace_panel.dart';
import 'package:alera/src/features/workbench/presentation/simple_workspace_panel_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'empty panel offers exactly four tools and Terminal without opening one',
    (tester) async {
      final selected = <String>[];
      var terminals = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SimpleWorkspacePanelView(
              panel: const SimpleWorkspacePanel(),
              tabs: const [],
              onSelect: selected.add,
              onClose: (_) {},
              onNewTerminal: () => terminals++,
              onHide: () {},
              content: const Text('Must Not Mount'),
            ),
          ),
        ),
      );
      expect(find.text('Must Not Mount'), findsNothing);
      expect(find.text('Panel is Empty'), findsOneWidget);
      for (final label in [
        'Explorer',
        'Search',
        'Source Control',
        'Pull Request',
        'Terminal',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(selected, isEmpty);
      await tester.tap(find.text('Search'));
      expect(selected, ['tool:search']);
      await tester.tap(find.text('Terminal'));
      expect(terminals, 1);
    },
  );

  testWidgets(
    'tab strip selects and closes tools and handles narrow overflow',
    (tester) async {
      final selected = <String>[];
      final closed = <String>[];
      final panel = SimpleWorkspacePanel(
        tabKeys: [for (final tool in SimpleWorkspaceTool.values) tool.key],
        activeKey: 'tool:search',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 240,
                height: 500,
                child: SimpleWorkspacePanelView(
                  panel: panel,
                  tabs: const [],
                  onSelect: selected.add,
                  onClose: closed.add,
                  onNewTerminal: () {},
                  onHide: () {},
                  content: const Text('Selected Surface'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Selected Surface'), findsOneWidget);
      await tester.tap(find.text('Explorer'));
      expect(selected, ['tool:explorer']);
      await tester.tap(find.byTooltip('Close Explorer'));
      expect(closed, ['tool:explorer']);
    },
  );

  testWidgets('add tab sits after the chips while the strip has space', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 500,
              child: SimpleWorkspacePanelView(
                panel: const SimpleWorkspacePanel(
                  tabKeys: ['tool:search'],
                  activeKey: 'tool:search',
                ),
                tabs: const [],
                onSelect: (_) {},
                onClose: (_) {},
                onNewTerminal: () {},
                onHide: () {},
                content: const Text('Selected Surface'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final addTab = find.byTooltip('Add Tab');
    expect(addTab, findsOneWidget);
    expect(
      find.ancestor(of: addTab, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
    await tester.tap(addTab);
    await tester.pumpAndSettle();
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Source Control'), findsOneWidget);
    expect(find.text('Pull Request'), findsOneWidget);
  });

  testWidgets('add tab menu omits tools that are already open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 500,
              child: SimpleWorkspacePanelView(
                panel: const SimpleWorkspacePanel(
                  tabKeys: ['tool:search', 'tool:explorer'],
                  activeKey: 'tool:search',
                ),
                tabs: const [],
                onSelect: (_) {},
                onClose: (_) {},
                onNewTerminal: () {},
                onHide: () {},
                content: const Text('Selected Surface'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add Tab'));
    await tester.pumpAndSettle();
    expect(find.text('Source Control'), findsOneWidget);
    expect(find.text('Pull Request'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(AleraDropdownEntry<String>), findsNWidgets(3));
  });

  testWidgets('add tab pins beside Hide Panel when the strip overflows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 160,
              height: 500,
              child: SimpleWorkspacePanelView(
                panel: SimpleWorkspacePanel(
                  tabKeys: [
                    for (final tool in SimpleWorkspaceTool.values) tool.key,
                  ],
                  activeKey: 'tool:search',
                ),
                tabs: const [],
                onSelect: (_) {},
                onClose: (_) {},
                onNewTerminal: () {},
                onHide: () {},
                content: const Text('Selected Surface'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final addTab = find.byTooltip('Add Tab');
    expect(addTab, findsOneWidget);
    expect(
      find.ancestor(of: addTab, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );
  });

  testWidgets('add tab placement stays stable across frames at a tight width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              height: 500,
              child: SimpleWorkspacePanelView(
                panel: const SimpleWorkspacePanel(
                  tabKeys: ['tool:search', 'tool:explorer'],
                  activeKey: 'tool:search',
                ),
                tabs: const [],
                onSelect: (_) {},
                onClose: (_) {},
                onNewTerminal: () {},
                onHide: () {},
                content: const Text('Selected Surface'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final firstInside = find
        .ancestor(
          of: find.byTooltip('Add Tab'),
          matching: find.byType(SingleChildScrollView),
        )
        .evaluate()
        .isNotEmpty;
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    final laterInside = find
        .ancestor(
          of: find.byTooltip('Add Tab'),
          matching: find.byType(SingleChildScrollView),
        )
        .evaluate()
        .isNotEmpty;
    expect(laterInside, firstInside);
    expect(find.byTooltip('Add Tab'), findsOneWidget);
  });

  testWidgets('tool chip offers split actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimpleWorkspacePanelView(
            panel: const SimpleWorkspacePanel(
              tabKeys: ['tool:search'],
              activeKey: 'tool:search',
            ),
            tabs: const [],
            onSelect: (_) {},
            onClose: (_) {},
            onNewTerminal: () {},
            onHide: () {},
            onSplitGroup: (_, _) {},
            content: const Text('Selected Surface'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Search'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Split Down'), findsOneWidget);
    expect(find.text('Split Right'), findsOneWidget);
    expect(find.text('Close Others'), findsOneWidget);
    expect(find.text('Close Tabs to the Right'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pane Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Split Up'), findsOneWidget);
    expect(find.text('Close Split'), findsNothing);
  });
}
