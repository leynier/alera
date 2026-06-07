import 'package:alera/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_search_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search toolbar keeps refresh rightmost and toggles view icon', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _pumpSearchPanel(
      tester,
      container: container,
      workspace: _workspace(id: 'workspace-a', path: '/workspace-a'),
    );

    expect(find.byTooltip('View as tree'), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    expect(find.byIcon(Icons.format_list_bulleted), findsNothing);
    expect(
      tester.getCenter(find.byTooltip('Refresh')).dx,
      greaterThan(tester.getCenter(find.byTooltip('Collapse all')).dx),
    );

    await tester.tap(find.byTooltip('View as tree'));
    await tester.pump();

    expect(find.byTooltip('View as list'), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
  });

  testWidgets('toggles search ignored files action in toolbar', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _pumpSearchPanel(
      tester,
      container: container,
      workspace: _workspace(id: 'workspace-a', path: '/workspace-a'),
    );

    expect(find.byTooltip('Search ignored files'), findsOneWidget);
    expect(find.byTooltip('Ignore ignored files'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    expect(find.byTooltip('Search ignored files'), findsNothing);
    expect(find.byTooltip('Ignore ignored files'), findsOneWidget);
  });

  testWidgets('shows active replacement and filters after workspace switch', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final workspaceA = _workspace(id: 'workspace-a', path: '/workspace-a');
    final workspaceB = _workspace(id: 'workspace-b', path: '/workspace-b');
    final workspaceBController = container.read(
      workspaceSearchControllerProvider(workspaceB.id).notifier,
    );
    workspaceBController.setReplacement(workspaceB.path, 'replacement text');
    workspaceBController.setIncludePattern(workspaceB.path, 'lib/**');
    workspaceBController.setExcludePattern(workspaceB.path, 'build/**');

    await _pumpSearchPanel(tester, container: container, workspace: workspaceA);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(_textFieldWithValue('replacement text'), findsNothing);
    expect(_textFieldWithValue('lib/**'), findsNothing);
    expect(_textFieldWithValue('build/**'), findsNothing);

    await _pumpSearchPanel(tester, container: container, workspace: workspaceB);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(4));
    expect(_textFieldWithValue('replacement text'), findsOneWidget);
    expect(_textFieldWithValue('lib/**'), findsOneWidget);
    expect(_textFieldWithValue('build/**'), findsOneWidget);
  });
}

Future<void> _pumpSearchPanel(
  WidgetTester tester, {
  required ProviderContainer container,
  required Workspace workspace,
}) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 520,
            child: WorkspaceSearchPanel(
              workspace: workspace,
              onOpenMatch: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _textFieldWithValue(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.controller?.text == value,
  );
}

Workspace _workspace({required String id, required String path}) {
  final now = DateTime(2026, 1);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: id,
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}
