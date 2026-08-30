import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workbench_dialog_launchers_test_support.dart';

void main() {
  group('workbench dialog launchers', () {
    testWidgets('openSettingsDialog opens the settings dialog', (tester) async {
      await pumpFlowHarness(
        tester,
        controller: DialogLaunchersTestController(const WorkbenchState()),
        onPressed: (context, _) => openSettingsDialog(context),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Application'), findsWidgets);
    });

    testWidgets(
      'showRenameDialog validates empty values and returns trimmed text',
      (tester) async {
        String? result;

        await pumpFlowHarness(
          tester,
          controller: DialogLaunchersTestController(const WorkbenchState()),
          onPressed: (context, _) async {
            result = await showRenameDialog(
              context,
              title: 'Rename Project',
              labelText: 'Project Name',
              initialValue: 'Alera',
              confirmLabel: 'Rename',
            );
          },
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '   ');
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        expect(find.text('Project Name is required'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '  Workspace tools  ');
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();

        expect(result, 'Workspace tools');
      },
    );

    testWidgets('showRenameDialog supports Enter submission and cancel', (
      tester,
    ) async {
      String? submitted;
      String? cancelled = 'not-null';

      await pumpFlowHarness(
        tester,
        controller: DialogLaunchersTestController(const WorkbenchState()),
        onPressed: (context, _) async {
          submitted = await showRenameDialog(
            context,
            title: 'Rename Project',
            labelText: 'Project Name',
            initialValue: 'Alera',
            confirmLabel: 'Rename',
          );
          cancelled = await showRenameDialog(
            context,
            title: 'Rename Project',
            labelText: 'Project Name',
            initialValue: 'Alera',
            confirmLabel: 'Rename',
          );
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'From keyboard');
      await tester.testTextInput.receiveAction(.done);
      await tester.pumpAndSettle();

      expect(submitted, 'From keyboard');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(cancelled, isNull);
    });

    testWidgets(
      'showAddProjectFlow adds a local project and shows success feedback',
      (tester) async {
        final controller = DialogLaunchersTestController(
          const WorkbenchState(),
        );

        await pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showAddProjectFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Project Path'),
          '/projects/notes',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
        await tester.pumpAndSettle();

        expect(controller.addedLocalPath, '/projects/notes');
        expect(controller.addedLocalName, 'notes');
        expect(find.text('Project added'), findsOneWidget);
      },
    );

    testWidgets(
      'showAddProjectFlow shows progress for clone flows and completes',
      (tester) async {
        final controller = DialogLaunchersTestController(const WorkbenchState())
          ..cloneCompleter = Completer<Project>();

        await pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showAddProjectFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clone From URL'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Git URL'),
          'https://github.com/acme/alera.git',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Destination Folder'),
          '/projects/alera',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
        await tester.pump();

        expect(find.text('Cloning repository…'), findsOneWidget);

        controller.cloneCompleter!.complete(
          buildProject('project-clone', 'Alera'),
        );
        await tester.pumpAndSettle();

        expect(controller.clonedProjectCall, (
          gitUrl: 'https://github.com/acme/alera.git',
          destinationPath: '/projects/alera',
          name: 'alera',
        ));
        expect(find.text('Project cloned'), findsOneWidget);
      },
    );

    testWidgets('showAddProjectFlow surfaces controller errors', (
      tester,
    ) async {
      final controller = DialogLaunchersTestController(const WorkbenchState())
        ..addLocalError = Exception('Could not add project');

      await pumpFlowHarness(
        tester,
        controller: controller,
        onPressed: (context, ref) => showAddProjectFlow(context, ref),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Project Path'),
        '/projects/broken',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
      await tester.pumpAndSettle();

      expect(find.text('Exception: Could not add project'), findsOneWidget);
    });

    testWidgets(
      'showCreateWorkspaceFlow shows an empty state when no git project is available',
      (tester) async {
        final controller = DialogLaunchersTestController(
          WorkbenchState(
            projects: <Project>[
              buildProject('folder-project', 'Notes', kind: .folder),
            ],
          ),
        );

        await pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await openManualWorkspaceDialog(tester);

        expect(find.text('No Git projects yet'), findsOneWidget);
        expect(
          find.text(
            'Linked workspaces require a Git project. Add one to get started.',
          ),
          findsOneWidget,
        );
        expect(controller.createdWorkspaceCall, isNull);
      },
    );

    testWidgets(
      'showCreateWorkspaceFlow creates a workspace and shows success',
      (tester) async {
        final project = buildProject('project-1', 'Alera');
        final controller = DialogLaunchersTestController(
          WorkbenchState(projects: <Project>[project]),
        )..sourceBranches = <String>['main'];

        await pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await openManualWorkspaceDialog(tester);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'New Branch Name *'),
          'feature/coverage',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Workspace'));
        await tester.pumpAndSettle();

        expect(controller.createdWorkspaceCall, (
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/coverage',
          reuseExistingBranch: false,
          name: 'feature/coverage',
          parentWorkspaceId: null,
        ));
        expect(find.text('Workspace created'), findsOneWidget);
      },
    );

    testWidgets(
      'showCreateWorkspaceFlow toasts and resets when Create Another is on',
      (tester) async {
        final project = buildProject('project-1', 'Alera');
        final controller = DialogLaunchersTestController(
          WorkbenchState(projects: <Project>[project]),
        )..sourceBranches = <String>['main'];

        await pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await openManualWorkspaceDialog(tester);
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

        expect(find.text('Workspace created'), findsOneWidget);
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
      },
    );

    testWidgets('showCreateWorkspaceFlow warns when setup steps fail', (
      tester,
    ) async {
      final project = buildProject('project-1', 'Alera');
      final controller =
          DialogLaunchersTestController(
              WorkbenchState(projects: <Project>[project]),
            )
            ..sourceBranches = <String>['main']
            ..setupReport = const WorktreeSetupReport(
              steps: <WorktreeSetupStepReport>[
                WorktreeSetupStepReport(
                  kind: .command,
                  label: 'make bootstrap',
                  succeeded: false,
                  message: 'failed',
                ),
              ],
            );

      await pumpFlowHarness(
        tester,
        controller: controller,
        onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await openManualWorkspaceDialog(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New Branch Name *'),
        'feature/setup-warning',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Workspace created with setup warnings: 1 setup action failed',
        ),
        findsOneWidget,
      );
      expect(find.text('Workspace created'), findsNothing);
    });

    testWidgets('showCreateWorkspaceFlow warns when the parent link fails', (
      tester,
    ) async {
      final project = buildProject('project-1', 'Alera');
      final controller =
          DialogLaunchersTestController(
              WorkbenchState(projects: <Project>[project]),
            )
            ..sourceBranches = <String>['main']
            ..parentLinkError = 'Parent workspace not found';

      await pumpFlowHarness(
        tester,
        controller: controller,
        onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await openManualWorkspaceDialog(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New Branch Name *'),
        'feature/orphan',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();

      expect(
        find.text('Workspace created, but parent link failed'),
        findsOneWidget,
      );
      expect(find.text('Workspace created'), findsNothing);
    });

    testWidgets('showCreateWorkspaceFlow surfaces controller errors', (
      tester,
    ) async {
      final project = buildProject('project-1', 'Alera');
      final controller =
          DialogLaunchersTestController(
              WorkbenchState(projects: <Project>[project]),
            )
            ..sourceBranches = <String>['main']
            ..createWorkspaceError = Exception('Workspace failed');

      await pumpFlowHarness(
        tester,
        controller: controller,
        onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await openManualWorkspaceDialog(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New Branch Name *'),
        'feature/error',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();

      expect(find.text('Exception: Workspace failed'), findsOneWidget);
    });
  });
}

Future<void> openManualWorkspaceDialog(WidgetTester tester) async {
  await tester.tap(find.text('Manual'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue Manually'));
  await tester.pumpAndSettle();
}
