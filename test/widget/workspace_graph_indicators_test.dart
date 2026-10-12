import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/icons/alera_linked_worktree_icon.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_graph_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Workspace workspace({
    WorkspaceKind kind = WorkspaceKind.linked,
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
      status: .active,
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
    testWidgets('shows the project-folder location for a shared workspace', (
      tester,
    ) async {
      await pump(tester, WorkspaceRoleBadge(workspace: workspace(kind: .main)));
      expect(find.byIcon(AleraIcons.workspaceMain), findsOneWidget);
      expect(find.byTooltip('Project folder'), findsOneWidget);
      expect(find.text('default'), findsNothing);
      expect(find.text('Primary'), findsNothing);
      expect(find.text('Child'), findsNothing);
    });

    testWidgets('shows linked-worktree location independently of parentage', (
      tester,
    ) async {
      await pump(
        tester,
        WorkspaceRoleBadge(workspace: workspace(parentWorkspaceId: 'parent')),
      );
      expect(find.byType(AleraLinkedWorktreeIcon), findsOneWidget);
      expect(find.byIcon(AleraIcons.split), findsOneWidget);
      expect(find.byIcon(AleraIcons.gitBranch), findsNothing);
      expect(AleraLinkedWorktreeIcon.quarterTurns, 1);
      expect(find.byTooltip('Linked worktree'), findsOneWidget);
      expect(find.text('default'), findsNothing);
      expect(find.text('Child'), findsNothing);
      expect(find.text('Primary'), findsNothing);
    });

    testWidgets('shows linked-worktree location for an unparented task', (
      tester,
    ) async {
      await pump(tester, WorkspaceRoleBadge(workspace: workspace()));
      expect(find.byType(AleraLinkedWorktreeIcon), findsOneWidget);
      expect(find.byIcon(AleraIcons.split), findsOneWidget);
      expect(
        tester
            .widget<RotatedBox>(
              find.descendant(
                of: find.byType(AleraLinkedWorktreeIcon),
                matching: find.byType(RotatedBox),
              ),
            )
            .quarterTurns,
        1,
      );
      expect(AleraLinkedWorktreeIcon.quarterTurns, 1);
      expect(find.byTooltip('Linked worktree'), findsOneWidget);
      expect(find.text('default'), findsNothing);
      expect(find.text('Primary'), findsNothing);
      expect(find.text('Child'), findsNothing);
    });

    test('hasRole matches the rendered roles', () {
      expect(WorkspaceRoleBadge.hasRole(workspace(kind: .main)), isTrue);
      expect(
        WorkspaceRoleBadge.hasRole(workspace(parentWorkspaceId: 'p')),
        isTrue,
      );
      expect(WorkspaceRoleBadge.hasRole(workspace()), isTrue);
    });
  });
}
