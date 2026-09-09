import 'package:alera/src/features/workbench/domain/simple_workspace_panel.dart';
import 'package:alera/src/features/workbench/presentation/simple_workspace_panel_view.dart';
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
}
