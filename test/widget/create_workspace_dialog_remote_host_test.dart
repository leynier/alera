import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('New Workspace submits the selected remote host', (tester) async {
    String? submittedHostId;
    await _pumpDialog(
      tester,
      sshTargets: <SshTarget>[_target(id: 'ssh-box', alias: 'Build Mac')],
      onHostId: (hostId) => submittedHostId = hostId,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Host'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);

    await tester.tap(find.text('This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Mac'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/remote',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(submittedHostId, 'ssh-box');
  });

  testWidgets('New Workspace blocks a host that is not bootstrapped', (
    tester,
  ) async {
    var created = false;
    await _pumpDialog(
      tester,
      sshTargets: <SshTarget>[
        _target(
          id: 'ssh-box',
          alias: 'Build Mac',
          bootstrapStatus: SshBootstrapStatus.notInstalled,
        ),
      ],
      onHostId: (_) => created = true,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Mac (Not Bootstrapped)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/remote',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(created, isFalse);
    expect(find.textContaining('not bootstrapped'), findsWidgets);
  });

  testWidgets('New Workspace blocks an unreachable host', (tester) async {
    var created = false;
    await _pumpDialog(
      tester,
      sshTargets: <SshTarget>[
        _target(id: 'ssh-box', alias: 'Build Mac', lastStatus: 'unreachable'),
      ],
      onHostId: (_) => created = true,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Mac (Unreachable)'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New Branch Name *'),
      'feature/remote',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Workspace'));
    await tester.pumpAndSettle();

    expect(created, isFalse);
    expect(find.textContaining('unreachable'), findsWidgets);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<SshTarget> sshTargets,
  required ValueChanged<String?> onHostId,
}) async {
  final now = DateTime.utc(2026, 9, 8);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showDialog<WorkspaceCreationResult>(
                    context: context,
                    builder: (_) => CreateWorkspaceDialog(
                      projects: <Project>[project],
                      sshTargets: sshTargets,
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
                          }) async {
                            onHostId(hostId);
                            return WorkspaceCreationResult(
                              workspace: Workspace(
                                id: 'workspace-1',
                                projectId: project.id,
                                name: name ?? newBranchName,
                                branch: newBranchName,
                                path: project.repoPath,
                                createdAt: now,
                                updatedAt: now,
                                kind: .linked,
                                status: .active,
                                hostId: hostId ?? localWorkspaceHostId,
                              ),
                              setupReport: .empty,
                            );
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

SshTarget _target({
  required String id,
  required String alias,
  SshBootstrapStatus bootstrapStatus = SshBootstrapStatus.installed,
  String? lastStatus,
}) {
  final now = DateTime.utc(2026, 9, 8);
  return SshTarget(
    id: id,
    alias: alias,
    host: 'mac.example.test',
    port: 22,
    username: 'leynier',
    authKind: SshAuthKind.agent,
    createdAt: now,
    updatedAt: now,
    bootstrapStatus: bootstrapStatus,
    lastStatus: lastStatus,
  );
}
