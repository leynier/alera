import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workbench_dialog_launchers_test_support.dart';

void main() {
  group('workbench dialog launchers create workspace', () {
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

      expect(find.text('New Workspace - Settings'), findsNothing);
      expect(find.text('Workspace failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('New Workspace - Settings'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('feature/error'), findsWidgets);
    });

    testWidgets(
      'showCreateWorkspaceFlow keeps Create Another open and shows the error',
      (tester) async {
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
        await tester.tap(find.text('Create Another'));
        await tester.pump();
        await tester.tap(find.text('Create Workspace'));
        await tester.pumpAndSettle();

        expect(find.text('New Workspace - Settings'), findsOneWidget);
        expect(find.text('Workspace failed'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'New Branch Name *'),
              )
              .controller
              ?.text,
          'feature/error',
        );
      },
    );

    testWidgets(
      'showCreateWorkspaceFlow closes on create and keeps the app usable',
      (tester) async {
        final project = buildProject('project-1', 'Alera');
        final controller =
            DialogLaunchersTestController(
                WorkbenchState(projects: <Project>[project]),
              )
              ..sourceBranches = <String>['main']
              ..createCompleter = Completer<WorkspaceCreationResult>();

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
          'feature/background',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create Workspace'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('New Workspace - Settings'), findsNothing);
        expect(
          find.text('Creating workspace "feature/background"'),
          findsOneWidget,
        );
        expect(find.text('Open'), findsOneWidget);

        controller.createCompleter!.complete(
          WorkspaceCreationResult(
            workspace: buildWorkspace(
              id: 'workspace-created',
              projectId: project.id,
              name: 'feature/background',
            ),
            setupReport: .empty,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Workspace created'), findsOneWidget);
        expect(
          find.text('Creating workspace "feature/background"'),
          findsNothing,
        );
      },
    );
  });
}
