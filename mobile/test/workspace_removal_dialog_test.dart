import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_removal_dependency.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_removal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(
  WidgetTester tester,
  Future<void> Function(BuildContext) action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => action(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('branch removal dialog stays compact', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, (context) async {
      await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
      );
    });
    expect(
      tester.getSize(find.byKey(workspaceRemovalDialogWidthKey)).width,
      lessThanOrEqualTo(420),
    );
    expect(
      tester.getSize(find.byKey(workspaceRemovalDialogWidthKey)).width,
      lessThan(tester.view.physicalSize.width),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('owned branch offers keep, remove, and cancel', (tester) async {
    WorkspaceRemovalDecision? result;
    await open(tester, (context) async {
      result = await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
      );
    });
    expect(find.text('Remove Workspace?'), findsOneWidget);
    expect(
      find.textContaining('This removes the worktree for "Feature login".'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Remove also attempts safe deletion of "feature".'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Remove'))
          .autofocus,
      isTrue,
    );
    expect(find.text('Keep Branch'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(result?.deleteBranch, isTrue);
  });

  testWidgets('keep branch confirms removal without deleting the branch', (
    tester,
  ) async {
    WorkspaceRemovalDecision? result;
    await open(tester, (context) async {
      result = await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
      );
    });
    await tester.tap(find.widgetWithText(TextButton, 'Keep Branch'));
    await tester.pumpAndSettle();
    expect(result?.deleteBranch, isFalse);
  });

  testWidgets('cancel dismisses without a decision', (tester) async {
    var completed = false;
    WorkspaceRemovalDecision? result;
    await open(tester, (context) async {
      result = await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
      );
      completed = true;
    });
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('unknown branch omits keep branch and keeps the branch', (
    tester,
  ) async {
    WorkspaceRemovalDecision? result;
    await open(tester, (context) async {
      result = await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: '',
        ),
      );
    });
    expect(
      find.textContaining('The workspace branch is unknown'),
      findsOneWidget,
    );
    expect(find.text('Keep Branch'), findsNothing);
    expect(find.text('Delete Branch'), findsNothing);
    expect(find.textContaining('attempts safe deletion'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(result?.deleteBranch, isFalse);
  });

  testWidgets('reused branch omits keep branch and names the kept branch', (
    tester,
  ) async {
    WorkspaceRemovalDecision? result;
    await open(tester, (context) async {
      result = await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'main',
          reusesExistingBranch: true,
        ),
      );
    });
    expect(find.textContaining('Branch "main" will be kept.'), findsOneWidget);
    expect(find.text('Keep Branch'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(result?.deleteBranch, isFalse);
  });

  testWidgets(
    'main workspace omits keep branch and warns about shared checkout',
    (tester) async {
      WorkspaceRemovalDecision? result;
      await open(tester, (context) async {
        result = await showWorkspaceRemovalDialog(
          context,
          workspace: const WorkspaceSummary(
            id: 'ws-main',
            projectId: 'p-1',
            name: 'Main repo',
            path: '/repo',
            branch: 'main',
            kind: 'main',
          ),
        );
      });
      expect(
        find.textContaining(
          'Files, branches and other workspaces in the project folder will be kept.',
        ),
        findsOneWidget,
      );
      expect(find.text('Keep Branch'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(result?.deleteBranch, isFalse);
    },
  );

  testWidgets('main workspace with linked descendants shows unlink notice', (
    tester,
  ) async {
    await open(tester, (context) async {
      await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-main',
          projectId: 'p-1',
          name: 'Main repo',
          path: '/repo',
          branch: 'main',
          kind: 'main',
        ),
        cascadeCount: 3,
      );
    });
    expect(
      find.textContaining(
        'Files, branches and other workspaces in the project folder will be kept.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'This workspace has 2 linked descendants. They will be unlinked, not deleted.',
      ),
      findsOneWidget,
    );
    expect(find.text('Keep Branch'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('descendants notice informs that linked children are unlinked', (
    tester,
  ) async {
    await open(tester, (context) async {
      await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
        cascadeCount: 3,
      );
    });
    expect(
      find.textContaining(
        'This workspace has 2 linked descendants. They will be unlinked, not deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('dependent automations change label and set pause flag', (
    tester,
  ) async {
    WorkspaceRemovalDecision? result;
    await open(tester, (context) async {
      result = await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
        dependencies: const [
          WorkspaceRemovalDependency(
            id: 'dep-1',
            name: 'Nightly tests',
            activeRuns: 2,
            requiresPause: true,
          ),
        ],
      );
    });
    expect(find.textContaining('Nightly tests: 2 active runs'), findsOneWidget);
    expect(find.text('Pause And Remove'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pause And Remove'));
    await tester.pumpAndSettle();
    expect(result?.deleteBranch, isTrue);
    expect(result?.pauseAutomations, isTrue);
  });

  testWidgets(
    'keep branch with dependencies pauses automations without deleting branch',
    (tester) async {
      WorkspaceRemovalDecision? result;
      await open(tester, (context) async {
        result = await showWorkspaceRemovalDialog(
          context,
          workspace: const WorkspaceSummary(
            id: 'ws-1',
            projectId: 'p-1',
            name: 'Feature login',
            path: '/workspaces/feature-login',
            branch: 'feature',
          ),
          dependencies: const [
            WorkspaceRemovalDependency(
              id: 'dep-1',
              name: 'Nightly tests',
              activeRuns: 1,
              requiresPause: true,
            ),
          ],
        );
      });
      await tester.tap(find.widgetWithText(TextButton, 'Keep Branch'));
      await tester.pumpAndSettle();
      expect(result?.deleteBranch, isFalse);
      expect(result?.pauseAutomations, isTrue);
    },
  );

  testWidgets('impact summary appears above the worktree copy', (tester) async {
    await open(tester, (context) async {
      await showWorkspaceRemovalDialog(
        context,
        workspace: const WorkspaceSummary(
          id: 'ws-1',
          projectId: 'p-1',
          name: 'Feature login',
          path: '/workspaces/feature-login',
          branch: 'feature',
        ),
        impactSummary: 'Measured size: 4 KB across 3 entries.\n\n',
      );
    });
    expect(find.textContaining('Measured size: 4 KB'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
