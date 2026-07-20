import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/sleep_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const workspace = WorkspaceSummary(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Alera',
    path: '/repo/alera',
    branch: 'main',
  );

  testWidgets('Sleep Workspace Always Requires Confirmation', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showSleepWorkspaceDialog(
                context,
                workspace: workspace,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Sleep Workspace?'), findsOneWidget);
    expect(
      find.textContaining('All Tabs And Terminal Sessions'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('Sleep Workspace Returns Confirmation', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showSleepWorkspaceDialog(
                context,
                workspace: workspace,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sleep'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
