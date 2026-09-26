import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 21);

void main() {
  testWidgets(
    'a host the project is not on offers Add to Host and never loads branches',
    (tester) async {
      final harness = _Harness();
      await harness.openOnHost(tester, 'Build Mac');

      expect(
        find.text(
          'Alera is not on Build Mac yet. Add it to list branches and create workspaces there.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Add to Host'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Existing Path'), findsOneWidget);
      expect(_createButton(tester).onPressed, isNull);
      expect(harness.branchLoads, <String>['local']);
    },
  );

  testWidgets('adding shows progress, keeps Create off, then loads branches', (
    tester,
  ) async {
    final harness = _Harness()..gate = Completer<void>();
    await harness.openOnHost(tester, 'Build Mac');
    await tester.enterText(
      find.widgetWithText(TextField, 'Existing Path'),
      '/srv/alera',
    );
    await _tapAddToHost(tester);
    await tester.pump();

    expect(
      find.text(
        'Adding the project to the host. A clone can take a few minutes.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Add to Host'), findsNothing);
    expect(_createButton(tester).onPressed, isNull);
    expect(find.text('Back'), findsOneWidget);

    harness.gate!.complete();
    await tester.pumpAndSettle();

    expect(harness.adds, <(String, String?)>[('ssh-box', '/srv/alera')]);
    expect(find.textContaining('is not on Build Mac yet'), findsNothing);
    expect(harness.branchLoads, <String>['local', 'ssh-box']);

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/remote',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(harness.createdOn, 'ssh-box');
    expect(harness.createdFrom, 'remote-main');
  });

  testWidgets('a failed add shows the runtime message and stays retryable', (
    tester,
  ) async {
    final harness = _Harness()
      ..addError = StateError('The host could not clone the repository.');
    await harness.openOnHost(tester, 'Build Mac');
    await _tapAddToHost(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('The host could not clone the repository.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Add to Host'), findsOneWidget);
    expect(_createButton(tester).onPressed, isNull);
    expect(harness.branchLoads, <String>['local']);
  });

  testWidgets('a folder project explains why it cannot be added', (
    tester,
  ) async {
    final harness = _Harness(kind: ProjectKind.folder);
    await harness.openOnHost(tester, 'Build Mac');

    expect(
      find.text(
        'Alera is a folder project, which lives on one host. Only Git projects can be added to more hosts.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add to Host'), findsNothing);
    expect(_createButton(tester).onPressed, isNull);
  });

  testWidgets('a host the project is already on needs no enrollment', (
    tester,
  ) async {
    final harness = _Harness(
      checkouts: const <ProjectCheckout>[
        ProjectCheckout(hostId: 'ssh-box', path: '/srv/alera'),
      ],
    );
    await harness.openOnHost(tester, 'Build Mac');

    expect(find.text('Add to Host'), findsNothing);
    expect(harness.branchLoads, <String>['local', 'ssh-box']);
    expect(_createButton(tester).onPressed, isNotNull);
  });
}

Future<void> _tapAddToHost(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Add to Host');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

FilledButton _createButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Create Workspace'),
  );
}

class _Harness {
  _Harness({
    ProjectKind kind = ProjectKind.gitRepository,
    List<ProjectCheckout> checkouts = const <ProjectCheckout>[],
  }) : project = Project(
         id: 'project-1',
         name: 'Alera',
         repoPath: '/repo/alera',
         createdAt: _now,
         updatedAt: _now,
         kind: kind,
         checkouts: checkouts,
       );

  final Project project;
  final List<String> branchLoads = <String>[];
  final List<(String, String?)> adds = <(String, String?)>[];
  Completer<void>? gate;
  Object? addError;
  String? createdOn;
  String? createdFrom;

  Future<void> openOnHost(WidgetTester tester, String alias) async {
    final controller = ProjectHostEnrollmentController((
      project,
      hostId,
      existingPath,
    ) async {
      adds.add((hostId, existingPath));
      await gate?.future;
      if (addError case final error?) {
        throw error;
      }
      return projectWithCheckout(
        project,
        ProjectCheckout(hostId: hostId, path: existingPath ?? '/cloned'),
      );
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<WorkspaceCreationResult>(
                context: context,
                builder: (_) => _dialog(controller),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(alias));
    await tester.pumpAndSettle();
  }

  Widget _dialog(ProjectHostEnrollmentController controller) {
    return CreateWorkspaceDialog(
      projects: <Project>[project],
      hostEnrollment: controller,
      sshTargets: <SshTarget>[
        SshTarget(
          id: 'ssh-box',
          alias: 'Build Mac',
          host: 'mac.example.test',
          port: 22,
          username: 'leynier',
          authKind: SshAuthKind.agent,
          createdAt: _now,
          updatedAt: _now,
          bootstrapStatus: SshBootstrapStatus.installed,
        ),
      ],
      loadHostBranchCatalog: (project, hostId) async {
        final host = hostId ?? 'local';
        branchLoads.add(host);
        if (!project.isOnHost(hostId)) {
          throw StateError('project is not registered on host $host');
        }
        final branches = host == 'local' ? ['main'] : ['remote-main'];
        return ProjectBranchCatalog(
          projectId: project.id,
          hostId: host,
          branches: branches,
          localBranches: branches.toSet(),
        );
      },
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
            hostId,
            issueUrl,
          }) async {
            createdOn = hostId;
            createdFrom = sourceBranch;
            return WorkspaceCreationResult(
              workspace: Workspace(
                id: 'workspace-1',
                projectId: project.id,
                name: name ?? newBranchName,
                branch: newBranchName,
                path: project.repoPath,
                createdAt: _now,
                updatedAt: _now,
                kind: .linked,
                status: .active,
                hostId: hostId ?? 'local',
              ),
              setupReport: .empty,
            );
          },
    );
  }
}
