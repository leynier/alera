import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:alera/src/features/workbench/presentation/workspace_host_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_host_view_fixtures.dart';

void main() {
  testWidgets(
    'the host sits on the first step and its change keeps the branch',
    (tester) async {
      final loads = <String>[];
      String? source;
      String? submittedHostId;
      await _pumpDialog(
        tester,
        hosts: [remoteHostView('ssh-box', 'Build Mac')],
        onHostId: (hostId) => submittedHostId = hostId,
        onSourceBranch: (value) => source = value,
        loadHostBranchCatalog: (project, hostId) async {
          final host = hostId ?? 'local';
          loads.add(host);
          final branches = host == 'local'
              ? ['main', 'shared']
              : ['remote-main', 'shared'];
          return ProjectBranchCatalog(
            projectId: project.id,
            hostId: host,
            branches: branches,
            localBranches: branches.toSet(),
          );
        },
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Host'), findsOneWidget);
      await tester.tap(find.text('shared'));
      await tester.pumpAndSettle();
      await _pickHost(tester, 'Build Mac');

      expect(loads, ['local', 'ssh-box']);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New Branch Name *'),
        'feature/remote',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Workspace'));
      await tester.pumpAndSettle();

      expect(submittedHostId, 'ssh-box');
      expect(source, 'shared');
    },
  );

  testWidgets('hosts that cannot take a workspace are listed but disabled', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      hosts: [
        remoteHostView(
          'setup',
          'Build Mac',
          status: const RemoteHostNeedsSetup(),
        ),
        remoteHostView(
          'installing',
          'Linux Box',
          status: const RemoteHostInstalling(),
        ),
        remoteHostView(
          'broken',
          'GPU Rig',
          status: const RemoteHostError(detail: 'Permission denied'),
        ),
      ],
      onHostId: (_) {},
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device'));
    await tester.pumpAndSettle();

    expect(find.text('Build Mac (Needs Setup)'), findsOneWidget);
    expect(find.text('Linux Box (Installing…)'), findsOneWidget);
    expect(find.text('GPU Rig (Error)'), findsOneWidget);

    await tester.tap(find.text('Build Mac (Needs Setup)'));
    await tester.pumpAndSettle();
    expect(_picker(tester).hostId, isNull);
  });

  testWidgets('an offline host stays selectable and explains itself', (
    tester,
  ) async {
    String? opened;
    String? submittedHostId;
    await _pumpDialog(
      tester,
      hosts: [
        remoteHostView(
          'ssh-box',
          'Build Mac',
          status: const RemoteHostOffline(),
        ),
      ],
      onHostId: (hostId) => submittedHostId = hostId,
      onOpenHost: (hostId) => opened = hostId,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _pickHost(tester, 'Build Mac');

    expect(find.text(workspaceHostOfflineMessage('Build Mac')), findsOneWidget);
    await tester.tap(find.text('Open Host'));
    await tester.pumpAndSettle();
    expect(opened, 'ssh-box');

    await tester.tap(find.text('Continue'));
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

  testWidgets('a remote-only project on a host without setup cannot continue', (
    tester,
  ) async {
    String? opened;
    await _pumpDialog(
      tester,
      primaryHostId: 'ssh-box',
      hosts: [
        remoteHostView(
          'ssh-box',
          'Build Mac',
          status: const RemoteHostNeedsSetup(),
        ),
      ],
      onHostId: (_) {},
      onOpenHost: (hostId) => opened = hostId,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('The Alera runtime is not installed on Build Mac yet.'),
      findsOneWidget,
    );
    expect(_continueButton(tester).onPressed, isNull);
    await tester.tap(find.text('Open Host'));
    await tester.pumpAndSettle();
    expect(opened, 'ssh-box');
  });

  testWidgets('without hosts the picker offers Add Host', (tester) async {
    var added = 0;
    await _pumpDialog(
      tester,
      hosts: const <RemoteHostView>[],
      onHostId: (_) {},
      onAddHost: () => added++,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text(workspaceHostNoHostsMessage), findsOneWidget);
    await tester.tap(find.text('Add Host'));
    await tester.pumpAndSettle();
    expect(added, 1);
  });

  testWidgets('a removed host falls back to This Device', (tester) async {
    final hosts = ValueNotifier<List<RemoteHostView>>([
      remoteHostView('ssh-box', 'Build Mac'),
    ]);
    addTearDown(hosts.dispose);
    await _pumpDialog(tester, hostsListenable: hosts, onHostId: (_) {});
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _pickHost(tester, 'Build Mac');
    expect(_picker(tester).hostId, 'ssh-box');

    hosts.value = const <RemoteHostView>[];
    await tester.pumpAndSettle();
    expect(_picker(tester).hostId, isNull);
  });
}

Future<void> _pickHost(WidgetTester tester, String label) async {
  await tester.tap(find.text('This Device'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

WorkspaceHostPicker _picker(WidgetTester tester) =>
    tester.widget<WorkspaceHostPicker>(find.byType(WorkspaceHostPicker));

FilledButton _continueButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Continue'),
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  List<RemoteHostView> hosts = const <RemoteHostView>[],
  ValueListenable<List<RemoteHostView>>? hostsListenable,
  required ValueChanged<String?> onHostId,
  ValueChanged<String>? onOpenHost,
  VoidCallback? onAddHost,
  String primaryHostId = localWorkspaceHostId,
  ValueChanged<String>? onSourceBranch,
  Future<ProjectBranchCatalog> Function(Project, String?)?
  loadHostBranchCatalog,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final now = DateTime.utc(2026, 9, 8);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
    primaryHostId: primaryHostId,
    checkouts: <ProjectCheckout>[
      if (primaryHostId != localWorkspaceHostId)
        ProjectCheckout(hostId: primaryHostId, path: '/srv/alera'),
    ],
  );
  final listenable =
      hostsListenable ?? ValueNotifier<List<RemoteHostView>>(hosts);
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
                    builder: (_) =>
                        ValueListenableBuilder<List<RemoteHostView>>(
                          valueListenable: listenable,
                          builder: (context, hosts, _) => CreateWorkspaceDialog(
                            projects: <Project>[project],
                            hosts: hosts,
                            onOpenHost: onOpenHost,
                            onAddHost: onAddHost,
                            loadHostBranchCatalog: loadHostBranchCatalog,
                            loadBranches: (_) async => const <String>['main'],
                            checkBranchExists: (_, _) async => false,
                            getProjectActiveBranch: (_) => null,
                            getProjectWorkspaceBranches: (_) =>
                                const <String>{},
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
                                  onHostId(hostId);
                                  onSourceBranch?.call(sourceBranch);
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
