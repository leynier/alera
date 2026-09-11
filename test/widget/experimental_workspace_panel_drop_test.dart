import 'package:alera/src/features/workbench/domain/experimental_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/presentation/experimental_workspace_panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dropping a right-panel tab onto the main surface reports the move',
    (tester) async {
      final moves =
          <
            ({
              String key,
              String targetGroupId,
              WorkbenchDropZone zone,
              ExperimentalPanelTree source,
            })
          >[];
      final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
          .select('tool:search');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 500,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 360,
                    child: ExperimentalWorkspacePanelView(
                      workspaceId: 'workspace',
                      panel: panel,
                      tabs: const [],
                      onSelect: (_) {},
                      onClose: (_) {},
                      onNewTerminal: () {},
                      onHide: () {},
                      onMoveTab: ({
                        required key,
                        required targetGroupId,
                        required zone,
                        required source,
                        index,
                      }) {},
                      content: const Text('Right Surface'),
                    ),
                  ),
                  Expanded(
                    child: ExperimentalMainDropSurface(
                      workspaceId: 'workspace',
                      groupId: 'workspace/experimental-main',
                      onMoveTab:
                          ({
                            required key,
                            required targetGroupId,
                            required zone,
                            required source,
                            index,
                          }) {
                            moves.add((
                              key: key,
                              targetGroupId: targetGroupId,
                              zone: zone,
                              source: source,
                            ));
                          },
                      child: const ColoredBox(
                        color: Color(0xFF111111),
                        child: Center(child: Text('Main Surface')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final chip = find.text('Search');
      final gesture = await tester.startGesture(tester.getCenter(chip));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(find.text('Main Surface')));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moves, isNotEmpty);
      expect(moves.single.key, 'tool:search');
      expect(moves.single.source, ExperimentalPanelTree.right);
      expect(moves.single.targetGroupId, 'workspace/experimental-main');
    },
  );
}
