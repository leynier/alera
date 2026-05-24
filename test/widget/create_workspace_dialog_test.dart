import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits the selected source branch and branch name', (
    tester,
  ) async {
    CreateWorkspaceResult? result;
    final project = _project();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<CreateWorkspaceResult>(
                      context: context,
                      builder: (_) => CreateWorkspaceDialog(
                        project: project,
                        branches: const <String>['main', 'origin/main'],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New branch name'),
      'feature/terminal-tabs',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace name (optional)'),
      'Terminal tabs',
    );
    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sourceBranch, 'main');
    expect(result!.newBranchName, 'feature/terminal-tabs');
    expect(result!.name, 'Terminal tabs');
  });

  testWidgets(
    'requires source branch and new branch when no branch list is provided',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    showDialog<CreateWorkspaceResult>(
                      context: context,
                      builder: (_) => CreateWorkspaceDialog(
                        project: _project(),
                        branches: const <String>[],
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create workspace'));
      await tester.pumpAndSettle();

      expect(find.text('Source branch is required'), findsOneWidget);
      expect(find.text('New branch name is required'), findsOneWidget);
    },
  );
}

Project _project() {
  final now = DateTime.utc(2026, 5, 21);
  return Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
}
