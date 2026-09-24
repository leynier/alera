part of 'create_workspace_dialog_test.dart';

void _registerCreateWorkspaceDialogSourceTests() {
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

  testWidgets('preselects the project default source branch', (tester) async {
    MockSubmitResult? result;
    final projects = <Project>[_project(id: 'alera', name: 'Alera'), _orca()];

    await _pumpDialogLauncher(
      tester,
      projects: projects,
      initialProject: _orca(),
      loadPreferredSourceBranch: (project) async {
        expect(project.id, 'orca');
        return 'develop';
      },
      loadBranches: (project) async {
        expect(project.id, 'orca');
        return const <String>['develop', 'main'];
      },
      onSubmit: (val) => result = val,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/from-develop',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.sourceBranch, 'develop');
  });
}
