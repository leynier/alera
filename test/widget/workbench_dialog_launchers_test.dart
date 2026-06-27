import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

void main() {
  group('workbench dialog launchers', () {
    testWidgets('openSettingsDialog opens the settings dialog', (tester) async {
      await _pumpFlowHarness(
        tester,
        controller: _DialogLaunchersTestController(const WorkbenchState()),
        onPressed: (context, _) => openSettingsDialog(context),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('General'), findsWidgets);
    });

    testWidgets(
      'showRenameDialog validates empty values and returns trimmed text',
      (tester) async {
        String? result;

        await _pumpFlowHarness(
          tester,
          controller: _DialogLaunchersTestController(const WorkbenchState()),
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
        expect(find.text('Project Name Is Required'), findsOneWidget);

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

      await _pumpFlowHarness(
        tester,
        controller: _DialogLaunchersTestController(const WorkbenchState()),
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submitted, 'From keyboard');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(cancelled, isNull);
    });

    testWidgets(
      'showAddProjectFlow adds a local project and shows success feedback',
      (tester) async {
        final controller = _DialogLaunchersTestController(
          const WorkbenchState(),
        );

        await _pumpFlowHarness(
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
        expect(find.text('Project Added'), findsOneWidget);
      },
    );

    testWidgets(
      'showAddProjectFlow shows progress for clone flows and completes',
      (tester) async {
        final controller = _DialogLaunchersTestController(
          const WorkbenchState(),
        )..cloneCompleter = Completer<Project>();

        await _pumpFlowHarness(
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

        expect(find.text('Cloning Repository…'), findsOneWidget);

        controller.cloneCompleter!.complete(_project('project-clone', 'Alera'));
        await tester.pumpAndSettle();

        expect(controller.clonedProjectCall, (
          gitUrl: 'https://github.com/acme/alera.git',
          destinationPath: '/projects/alera',
          name: 'alera',
        ));
        expect(find.text('Project Cloned'), findsOneWidget);
      },
    );

    testWidgets('showAddProjectFlow surfaces controller errors', (
      tester,
    ) async {
      final controller = _DialogLaunchersTestController(const WorkbenchState())
        ..addLocalError = Exception('Could not add project');

      await _pumpFlowHarness(
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
        final controller = _DialogLaunchersTestController(
          WorkbenchState(
            projects: <Project>[
              _project('folder-project', 'Notes', kind: ProjectKind.folder),
            ],
          ),
        );

        await _pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('No Git Projects Yet'), findsOneWidget);
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
        final project = _project('project-1', 'Alera');
        final controller = _DialogLaunchersTestController(
          WorkbenchState(projects: <Project>[project]),
        )..sourceBranches = <String>['main'];

        await _pumpFlowHarness(
          tester,
          controller: controller,
          onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
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
        ));
        expect(find.text('Workspace Created'), findsOneWidget);
      },
    );

    testWidgets('showCreateWorkspaceFlow surfaces controller errors', (
      tester,
    ) async {
      final project = _project('project-1', 'Alera');
      final controller =
          _DialogLaunchersTestController(
              WorkbenchState(projects: <Project>[project]),
            )
            ..sourceBranches = <String>['main']
            ..createWorkspaceError = Exception('Workspace failed');

      await _pumpFlowHarness(
        tester,
        controller: controller,
        onPressed: (context, ref) => showCreateWorkspaceFlow(context, ref),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
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

Future<void> _pumpFlowHarness(
  WidgetTester tester, {
  required _DialogLaunchersTestController controller,
  required Future<void> Function(BuildContext context, WidgetRef ref) onPressed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workbenchControllerProvider.overrideWith(() => controller),
        gitBackendProvider.overrideWithValue(FakeGitBackend()),
        settingsControllerProvider.overrideWith(
          () => _DialogLaunchersSettingsController(AleraSettings.defaults),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Center(
                child: Consumer(
                  builder: (context, ref, _) {
                    return FilledButton(
                      onPressed: () => onPressed(context, ref),
                      child: const Text('Open'),
                    );
                  },
                ),
              ),
              const AleraToastHost(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Project _project(
  String id,
  String name, {
  ProjectKind kind = ProjectKind.gitRepository,
}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: now,
    updatedAt: now,
    kind: kind,
  );
}

Workspace _workspace({
  required String id,
  required String projectId,
  required String name,
}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: 'main',
    path: '/repo/$projectId/$id',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
    sourceBranch: 'main',
  );
}

class _DialogLaunchersTestController extends WorkbenchController {
  _DialogLaunchersTestController(this._seed);

  final WorkbenchState _seed;

  String? addedLocalPath;
  String? addedLocalName;
  Exception? addLocalError;
  Completer<Project>? cloneCompleter;
  ({String gitUrl, String destinationPath, String? name})? clonedProjectCall;
  List<String> sourceBranches = const <String>['main'];
  Exception? createWorkspaceError;
  ({
    Project project,
    String sourceBranch,
    String newBranchName,
    bool reuseExistingBranch,
    String? name,
  })?
  createdWorkspaceCall;

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<Project> addLocalProject({required String path, String? name}) async {
    addedLocalPath = path;
    addedLocalName = name;
    if (addLocalError case final Exception error) {
      throw error;
    }
    return _project('project-local', name ?? 'notes');
  }

  @override
  Future<Project> cloneProject({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) async {
    clonedProjectCall = (
      gitUrl: gitUrl,
      destinationPath: destinationPath,
      name: name,
    );
    if (cloneCompleter case final Completer<Project> completer) {
      return completer.future;
    }
    return _project('project-clone', name ?? 'clone');
  }

  @override
  Future<List<String>> listSourceBranches(Project project) async {
    return sourceBranches;
  }

  @override
  Future<Workspace> createWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    bool reuseExistingBranch = false,
    String? name,
  }) async {
    if (createWorkspaceError case final Exception error) {
      throw error;
    }
    createdWorkspaceCall = (
      project: project,
      sourceBranch: sourceBranch,
      newBranchName: newBranchName,
      reuseExistingBranch: reuseExistingBranch,
      name: name,
    );
    return _workspace(
      id: 'workspace-created',
      projectId: project.id,
      name: name ?? newBranchName,
    );
  }
}

class _DialogLaunchersSettingsController extends SettingsController {
  _DialogLaunchersSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}
