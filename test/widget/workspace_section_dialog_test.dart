import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/presentation/workspace_section_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30);
final _workspace = Workspace(
  id: 'w',
  projectId: 'p',
  name: 'Workspace',
  path: '/w',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
);

class _Controller extends WorkbenchController {
  int saves = 0;
  String? name;
  String? section;
  bool fail = false;
  @override
  Future<List<WorkspaceSection>> listWorkspaceSections() async => [
    WorkspaceSection(
      id: 'existing',
      name: 'Existing',
      createdAt: _now,
      updatedAt: _now,
    ),
  ];
  @override
  Future<void> saveWorkspaceSection(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    if (fail) throw StateError('Section no longer exists');
    saves++;
    name = newName;
    section = sectionId;
  }
}

Future<void> _open(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: aleraDarkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showWorkspaceSectionDialog(context, controller, _workspace),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(find.text('No Section'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creating is deferred until Save and Cancel creates nothing', (
    tester,
  ) async {
    final controller = _Controller();
    await _open(tester, controller);
    await _choose(tester, 'New Section');
    await tester.enterText(find.byType(TextField), ' New Work ');
    expect(controller.saves, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.saves, 0);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _choose(tester, 'New Section');
    await tester.enterText(find.byType(TextField), ' New Work ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.name, 'New Work');
    expect(controller.saves, 1);
    expect(find.text('Set Section'), findsNothing);
  });
  testWidgets('selects an existing section and keeps errors open for retry', (
    tester,
  ) async {
    final controller = _Controller()..fail = true;
    await _open(tester, controller);
    await _choose(tester, 'Existing');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Section no longer exists'), findsOneWidget);
    expect(find.text('Set Section'), findsOneWidget);
    controller.fail = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.section, 'existing');
    expect(controller.saves, 1);
  });
}
