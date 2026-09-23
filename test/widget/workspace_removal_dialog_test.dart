import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/presentation/workspace_removal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(
  WidgetTester tester,
  Future<void> Function(BuildContext) action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: aleraDarkTheme,
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
        workspaceName: 'Feature login',
        branch: 'feature',
        canDeleteBranch: true,
      );
    });
    expect(
      tester.getSize(find.byKey(workspaceRemovalDialogWidthKey)).width,
      lessThanOrEqualTo(AleraTokens.dialogCompactWidth),
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
        workspaceName: 'Feature login',
        branch: 'feature',
        canDeleteBranch: true,
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
        workspaceName: 'Feature login',
        branch: 'feature',
        canDeleteBranch: true,
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
        workspaceName: 'Feature login',
        branch: 'feature',
        canDeleteBranch: true,
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
        workspaceName: 'Feature login',
        branch: '',
        canDeleteBranch: false,
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
        workspaceName: 'Feature login',
        branch: 'main',
        canDeleteBranch: false,
      );
    });
    expect(find.textContaining('Branch "main" will be kept.'), findsOneWidget);
    expect(find.text('Keep Branch'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(result?.deleteBranch, isFalse);
  });

  testWidgets('impact summary appears above the worktree copy', (tester) async {
    await open(tester, (context) async {
      await showWorkspaceRemovalDialog(
        context,
        workspaceName: 'Feature login',
        branch: 'feature',
        canDeleteBranch: true,
        impactSummary: 'Measured size: 4 KB across 3 entries.\n\n',
      );
    });
    expect(find.textContaining('Measured size: 4 KB'), findsOneWidget);
    expect(find.text('Clean Up Workspace?'), findsNothing);
    expect(find.text('Clean Up'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
