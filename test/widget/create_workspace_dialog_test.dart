import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects a project, filters source branches, and submits', (
    tester,
  ) async {
    CreateWorkspaceResult? result;
    final projects = <Project>[_project(id: 'alera', name: 'Alera'), _orca()];

    await _pumpDialogLauncher(
      tester,
      projects: projects,
      loadBranches: (project) async {
        if (project.id == 'orca') {
          return const <String>['develop', 'feature/orchestration'];
        }
        return const <String>['main', 'origin/main'];
      },
      onResult: (value) => result = value,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search projects'),
      'orca',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orca'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search source branches'),
      'feature',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature/orchestration'));
    await tester.enterText(
      find.widgetWithText(TextField, 'New branch name'),
      'feature/workspace-imports',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace name (optional)'),
      'Workspace imports',
    );
    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.project.id, 'orca');
    expect(result!.sourceBranch, 'feature/orchestration');
    expect(result!.newBranchName, 'feature/workspace-imports');
    expect(result!.name, 'Workspace imports');
  });

  testWidgets('preselects the requested project and default branch', (
    tester,
  ) async {
    CreateWorkspaceResult? result;
    final projects = <Project>[_project(id: 'alera', name: 'Alera'), _orca()];

    await _pumpDialogLauncher(
      tester,
      projects: projects,
      initialProject: _orca(),
      loadBranches: (project) async {
        expect(project.id, 'orca');
        return const <String>['develop', 'main'];
      },
      onResult: (value) => result = value,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New branch name'),
      'feature/default-source',
    );
    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.project.id, 'orca');
    expect(result!.sourceBranch, 'main');
  });

  testWidgets('changing projects reloads source branches', (tester) async {
    CreateWorkspaceResult? result;
    final loadedProjectIds = <String>[];
    final projects = <Project>[_project(id: 'alera', name: 'Alera'), _orca()];

    await _pumpDialogLauncher(
      tester,
      projects: projects,
      loadBranches: (project) async {
        loadedProjectIds.add(project.id);
        if (project.id == 'orca') {
          return const <String>['release/orca'];
        }
        return const <String>['main'];
      },
      onResult: (value) => result = value,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orca'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New branch name'),
      'release/orca-workspace',
    );
    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();

    expect(loadedProjectIds, <String>['alera', 'orca']);
    expect(result, isNotNull);
    expect(result!.project.id, 'orca');
    expect(result!.sourceBranch, 'release/orca');
  });

  testWidgets(
    'requires source branch and new branch when no branch list is provided',
    (tester) async {
      await _pumpDialogLauncher(
        tester,
        projects: <Project>[_project()],
        loadBranches: (_) async => const <String>[],
        onResult: (_) {},
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create workspace'));
      await tester.pumpAndSettle();

      expect(find.text('Source branch is required'), findsOneWidget);
      expect(find.text('New branch name is required'), findsOneWidget);
    },
  );

  testWidgets('shows empty states for project and branch filters', (
    tester,
  ) async {
    await _pumpDialogLauncher(
      tester,
      projects: <Project>[_project()],
      loadBranches: (_) async => const <String>['main'],
      onResult: (_) {},
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search projects'),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No projects match "missing"'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search projects'),
      '',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search source branches'),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No source branches match "missing"'), findsOneWidget);
  });
}

Future<void> _pumpDialogLauncher(
  WidgetTester tester, {
  required List<Project> projects,
  required Future<List<String>> Function(Project project) loadBranches,
  required ValueChanged<CreateWorkspaceResult?> onResult,
  Project? initialProject,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onResult(
                    await showDialog<CreateWorkspaceResult>(
                      context: context,
                      builder: (_) => CreateWorkspaceDialog(
                        projects: projects,
                        initialProject: initialProject,
                        loadBranches: loadBranches,
                      ),
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
}

Project _project({String id = 'project-1', String name = 'Alera'}) {
  final now = DateTime.utc(2026, 5, 21);
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: now,
    updatedAt: now,
  );
}

Project _orca() => _project(id: 'orca', name: 'Orca');
