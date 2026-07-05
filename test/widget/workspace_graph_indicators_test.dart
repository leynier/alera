import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_graph_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Workspace workspace({
    WorkspaceKind kind = WorkspaceKind.linked,
    String hostId = 'local',
    int childCount = 0,
    List<String> tagIds = const <String>[],
    List<String> tagNames = const <String>[],
    String? parentWorkspaceId,
  }) {
    final now = DateTime(2026);
    return Workspace(
      id: 'ws-1',
      projectId: 'proj-1',
      name: 'Workspace',
      path: '/tmp/ws',
      createdAt: now,
      updatedAt: now,
      kind: kind,
      status: WorkspaceStatus.active,
      hostId: hostId,
      childCount: childCount,
      tagIds: tagIds,
      tagNames: tagNames,
      parentWorkspaceId: parentWorkspaceId,
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('WorkspaceRoleBadge', () {
    testWidgets('shows Default for the main workspace', (tester) async {
      await pump(
        tester,
        WorkspaceRoleBadge(workspace: workspace(kind: WorkspaceKind.main)),
      );
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('default'), findsNothing);
      expect(find.text('Primary'), findsNothing);
      expect(find.text('Child'), findsNothing);
    });

    testWidgets('renders nothing when the workspace has a parent', (
      tester,
    ) async {
      await pump(
        tester,
        WorkspaceRoleBadge(workspace: workspace(parentWorkspaceId: 'parent')),
      );
      expect(find.text('Default'), findsNothing);
      expect(find.text('default'), findsNothing);
      expect(find.text('Child'), findsNothing);
      expect(find.text('Primary'), findsNothing);
    });

    testWidgets('renders nothing for a plain linked workspace', (tester) async {
      await pump(tester, WorkspaceRoleBadge(workspace: workspace()));
      expect(find.text('Default'), findsNothing);
      expect(find.text('default'), findsNothing);
      expect(find.text('Primary'), findsNothing);
      expect(find.text('Child'), findsNothing);
    });

    test('hasRole matches the rendered roles', () {
      expect(
        WorkspaceRoleBadge.hasRole(workspace(kind: WorkspaceKind.main)),
        isTrue,
      );
      expect(
        WorkspaceRoleBadge.hasRole(workspace(parentWorkspaceId: 'p')),
        isFalse,
      );
      expect(WorkspaceRoleBadge.hasRole(workspace()), isFalse);
    });
  });

  group('WorkspaceGraphChips', () {
    testWidgets('renders nothing for a plain local workspace', (tester) async {
      expect(WorkspaceGraphChips.hasContent(workspace()), isFalse);
      await pump(tester, WorkspaceGraphChips(workspace: workspace()));
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('shows host, children and capped tags with overflow', (
      tester,
    ) async {
      final ws = workspace(
        hostId: 'remote-mac',
        childCount: 2,
        tagNames: const <String>['alpha', 'beta', 'gamma', 'delta'],
      );
      expect(WorkspaceGraphChips.hasContent(ws), isTrue);
      await pump(tester, WorkspaceGraphChips(workspace: ws));

      expect(find.text('remote-mac'), findsOneWidget);
      expect(find.text('2 Children'), findsOneWidget);
      expect(find.text('#alpha'), findsOneWidget);
      expect(find.text('#beta'), findsOneWidget);
      expect(find.text('#gamma'), findsOneWidget);
      // Fourth tag is hidden behind the overflow chip.
      expect(find.text('#delta'), findsNothing);
      expect(find.text('+1 Tags'), findsOneWidget);
    });

    testWidgets('uses singular Child label and hides the local host', (
      tester,
    ) async {
      final ws = workspace(childCount: 1);
      await pump(tester, WorkspaceGraphChips(workspace: ws));
      expect(find.text('1 Child'), findsOneWidget);
      expect(find.text('local'), findsNothing);
    });

    testWidgets('prefers tag names and drops blank entries', (tester) async {
      final ws = workspace(
        tagIds: const <String>['id-1', 'id-2'],
        tagNames: const <String>['frontend', '   ', ''],
      );
      await pump(tester, WorkspaceGraphChips(workspace: ws));
      expect(find.text('#frontend'), findsOneWidget);
      // Falls back to ids only when names are empty; blanks never appear.
      expect(find.text('#id-1'), findsNothing);
      expect(find.textContaining('Tags'), findsNothing);
    });
  });
}
