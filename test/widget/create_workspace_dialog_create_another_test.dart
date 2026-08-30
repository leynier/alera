import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Create Another keeps the dialog open and resets target fields', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 30);
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: now,
      updatedAt: now,
    );
    final createdBranches = <String>[];
    var createdCallbacks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showDialog<WorkspaceCreationResult>(
                    context: context,
                    builder: (_) => CreateWorkspaceDialog(
                      projects: <Project>[project],
                      loadBranches: (_) async => const <String>['main'],
                      checkBranchExists: (_, _) async => false,
                      getProjectActiveBranch: (_) => null,
                      getProjectWorkspaceBranches: (_) => const <String>{},
                      onCreateWorkspace:
                          ({
                            required project,
                            required sourceBranch,
                            required newBranchName,
                            required reuseExistingBranch,
                            name,
                            parentWorkspaceId,
                          }) async {
                            createdBranches.add(newBranchName);
                            return WorkspaceCreationResult(
                              workspace: Workspace(
                                id: 'workspace-${createdBranches.length}',
                                projectId: project.id,
                                name: name ?? newBranchName,
                                branch: newBranchName,
                                sourceBranch: sourceBranch,
                                path: project.repoPath,
                                createdAt: now,
                                updatedAt: now,
                                kind: .linked,
                                status: .active,
                              ),
                              setupReport: .empty,
                            );
                          },
                      onWorkspaceCreated: (_) => createdCallbacks += 1,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/one',
    );
    await tester.tap(find.text('Create Another'));
    await tester.pump();
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(createdBranches, <String>['feature/one']);
    expect(createdCallbacks, 1);
    expect(find.text('New Workspace - Settings'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'New Branch Name *'),
          )
          .controller
          ?.text,
      isEmpty,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/two',
    );
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(createdBranches, <String>['feature/one', 'feature/two']);
    expect(createdCallbacks, 2);
    expect(find.text('New Workspace - Settings'), findsOneWidget);
  });
}
