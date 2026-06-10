import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef MockSubmitResult = ({
  Project project,
  String sourceBranch,
  String newBranchName,
  String? name,
});

void main() {
  testWidgets('selects a project, filters source branches, and submits', (
    tester,
  ) async {
    MockSubmitResult? result;
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
      onSubmit: (val) => result = val,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search Projects'),
      'orca',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orca'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search Source Branches'),
      'feature',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature/orchestration'));
    await tester.pumpAndSettle();

    // Tap Continue to go to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/workspace-imports',
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace Name (Optional)'),
      'Workspace imports',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Workspace'));
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
    MockSubmitResult? result;
    final projects = <Project>[_project(id: 'alera', name: 'Alera'), _orca()];

    await _pumpDialogLauncher(
      tester,
      projects: projects,
      initialProject: _orca(),
      loadBranches: (project) async {
        expect(project.id, 'orca');
        return const <String>['develop', 'main'];
      },
      onSubmit: (val) => result = val,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap Continue to go to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/default-source',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.project.id, 'orca');
    expect(result!.sourceBranch, 'main');
  });

  testWidgets('changing projects reloads source branches', (tester) async {
    MockSubmitResult? result;
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
      onSubmit: (val) => result = val,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orca'));
    await tester.pumpAndSettle();

    // Tap Continue to go to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'release/orca-workspace',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(loadedProjectIds, <String>['alera', 'orca']);
    expect(result, isNotNull);
    expect(result!.sourceBranch, 'release/orca');
  });

  testWidgets(
    'requires source branch and new branch when no branch list is provided',
    (tester) async {
      await _pumpDialogLauncher(
        tester,
        projects: <Project>[_project()],
        loadBranches: (_) async => const <String>[],
        onSubmit: (_) {},
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Try to continue without source branch
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Source Branch Is Required'), findsOneWidget);

      // Input source branch and continue
      await tester.enterText(
        find.widgetWithText(TextField, 'Source Branch'),
        'main',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Try to create workspace without new branch name
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('New Branch Name Is Required'), findsOneWidget);
    },
  );

  testWidgets('shows empty states for project and branch filters', (
    tester,
  ) async {
    await _pumpDialogLauncher(
      tester,
      projects: <Project>[_project()],
      loadBranches: (_) async => const <String>['main'],
      onSubmit: (_) {},
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search Projects'),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No Projects Match "missing"'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search Projects'),
      '',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search Source Branches'),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No Source Branches Match "missing"'), findsOneWidget);
  });

  testWidgets('keeps branch picker scrollable on compact desktop heights', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpDialogLauncher(
      tester,
      projects: <Project>[_project()],
      loadBranches: (_) async => const <String>[
        'dev',
        'main',
        'origin',
        'origin/claude/integrate-vercel-analytics-01KxPescNmVV1Rr4T2RVutVg',
        'origin/dev',
        'origin/main',
        'origin/v0/leynier-24f7f479',
        'origin/v0/leynier-aac72b82',
      ],
      onSubmit: (_) {},
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('shows branch load errors and can cancel the dialog', (
    tester,
  ) async {
    MockSubmitResult? result;

    await _pumpDialogLauncher(
      tester,
      projects: <Project>[_project()],
      loadBranches: (_) async => throw StateError('cannot load branches'),
      onSubmit: (val) => result = val,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Bad state: cannot load branches'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets(
    'manual source branch input clears errors and can submit from the source field',
    (tester) async {
      MockSubmitResult? result;

      await _pumpDialogLauncher(
        tester,
        projects: <Project>[_project()],
        loadBranches: (_) async => const <String>[],
        onSubmit: (val) => result = val,
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Continue to validate Step 1 branch exists
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // We should remain in Step 1 due to validation or see error if we try to proceed without a branch
      final sourceField = find.widgetWithText(TextField, 'Source Branch');
      await tester.enterText(sourceField, 'release/manual');
      await tester.pumpAndSettle();

      // Tap Continue to go to Step 2
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Now we are in Step 2, test validation errors
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('New Branch Name Is Required'), findsOneWidget);

      final newBranchField = find.widgetWithText(
        TextField,
        'New Branch Name *',
      );
      await tester.enterText(newBranchField, 'feature/manual-source-submit');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.sourceBranch, 'release/manual');
      expect(result!.newBranchName, 'feature/manual-source-submit');
    },
  );

  testWidgets('submits from the new-branch and name fields', (tester) async {
    final results = <MockSubmitResult?>[];

    await _pumpDialogLauncher(
      tester,
      projects: <Project>[_project()],
      loadBranches: (_) async => const <String>[],
      onSubmit: results.add,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Source Branch'),
      'develop',
    );
    await tester.pumpAndSettle();

    // Go to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final newBranchField = find.widgetWithText(TextField, 'New Branch Name *');
    await tester.enterText(newBranchField, 'feature/new-branch-submit');
    await tester.pumpAndSettle();
    await tester.tap(newBranchField);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results.single, isNotNull);
    expect(results.single!.newBranchName, 'feature/new-branch-submit');

    results.clear();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Source Branch'),
      'develop',
    );
    await tester.pumpAndSettle();

    // Go to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/name-submit',
    );
    await tester.pumpAndSettle();
    final nameField = find.widgetWithText(
      TextField,
      'Workspace Name (Optional)',
    );
    await tester.enterText(nameField, 'Named workspace');
    await tester.pumpAndSettle();
    await tester.tap(nameField);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results.single, isNotNull);
    expect(results.single!.name, 'Named workspace');
  });
}

Future<void> _pumpDialogLauncher(
  WidgetTester tester, {
  required List<Project> projects,
  required Future<List<String>> Function(Project project) loadBranches,
  required ValueChanged<MockSubmitResult?> onSubmit,
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
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => CreateWorkspaceDialog(
                      projects: projects,
                      initialProject: initialProject,
                      loadBranches: loadBranches,
                      getProjectActiveBranch: (_) => null,
                      checkBranchExists: (_, _) async => false,
                      onCreateWorkspace:
                          ({
                            required project,
                            required sourceBranch,
                            required newBranchName,
                            name,
                          }) async {
                            onSubmit((
                              project: project,
                              sourceBranch: sourceBranch,
                              newBranchName: newBranchName,
                              name: name,
                            ));
                          },
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
