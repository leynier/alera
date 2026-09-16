import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/features/settings/presentation/panes/new_workspace_tools_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toggles and reorders new workspace tools', (tester) async {
    var selected = <WorkspaceTool>[
      WorkspaceTool.explorer,
      WorkspaceTool.search,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return NewWorkspaceToolsSettings(
                selected: selected,
                onChanged: (next) => setState(() => selected = next),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('New Workspace Tools'), findsOneWidget);
    expect(
      find.text(
        'Open these tools in the right panel of new workspaces. Drag to change their order. Existing workspaces keep their own panel.',
      ),
      findsOneWidget,
    );
    final checkboxes = tester
        .widgetList<AleraCheckbox>(find.byType(AleraCheckbox))
        .toList();
    expect(checkboxes, hasLength(4));
    expect(checkboxes[0].label, 'Explorer');
    expect(checkboxes[0].value, isTrue);
    expect(checkboxes[1].label, 'Search');
    expect(checkboxes[1].value, isTrue);
    expect(checkboxes[2].label, 'Source Control');
    expect(checkboxes[2].value, isFalse);

    await tester.tap(find.text('Source Control'));
    await tester.pump();
    expect(selected, [
      WorkspaceTool.explorer,
      WorkspaceTool.search,
      WorkspaceTool.sourceControl,
    ]);

    await tester.tap(find.text('Explorer'));
    await tester.pump();
    expect(selected, [WorkspaceTool.search, WorkspaceTool.sourceControl]);

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(1, 2);
    await tester.pump();
    expect(selected, [WorkspaceTool.sourceControl, WorkspaceTool.search]);
  });
}
