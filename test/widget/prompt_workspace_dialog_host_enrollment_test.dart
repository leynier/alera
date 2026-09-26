import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/prompt_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 21);

void main() {
  testWidgets(
    'From Prompt guards a host the project is not on and adds it in place',
    (tester) async {
      final branchLoads = <String>[];
      final requests = <PromptWorkspaceCreateRequest>[];
      final controller = ProjectHostEnrollmentController(
        (project, hostId, existingPath) async => projectWithCheckout(
          project,
          ProjectCheckout(hostId: hostId, path: '/cloned'),
        ),
      );
      addTearDown(controller.dispose);
      await _pumpDialog(
        tester,
        controller: controller,
        branchLoads: branchLoads,
        requests: requests,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Initial Prompt'),
        'Build the hosts dialog',
      );
      await tester.tap(find.text('This Device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build Mac'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Alera is not on Build Mac yet'), findsOne);
      expect(_submitButton(tester).onPressed, isNull);
      expect(branchLoads, <String>['local']);

      final add = find.widgetWithText(FilledButton, 'Add to Host');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(find.textContaining('is not on Build Mac yet'), findsNothing);
      expect(branchLoads, <String>['local', 'ssh-box']);

      final submit = find.text('Create And Start Agent');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(requests.single.hostId, 'ssh-box');
      expect(requests.single.sourceBranch, 'remote-main');
    },
  );
}

FilledButton _submitButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Create And Start Agent'),
      matching: find.bySubtype<FilledButton>(),
    ),
  );
}

class _SettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required ProjectHostEnrollmentController controller,
  required List<String> branchLoads,
  required List<PromptWorkspaceCreateRequest> requests,
}) async {
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: _now,
    updatedAt: _now,
  );
  final profile = AgentProfile(
    id: 'profile-1',
    name: 'Codex Builder',
    agentType: 'codex',
    command: 'codex',
    createdAt: _now,
    updatedAt: _now,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(_SettingsController.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<PromptWorkspaceDialogResult>(
                context: context,
                builder: (_) => PromptWorkspaceDialog(
                  projects: <Project>[project],
                  agentProfiles: <AgentProfile>[profile],
                  hostEnrollment: controller,
                  initialUseProjectCheckout: false,
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
                  loadBranches: (_) async => const <String>['main'],
                  loadHostBranchCatalog: (project, hostId) async {
                    final host = hostId ?? 'local';
                    branchLoads.add(host);
                    if (!project.isOnHost(hostId)) {
                      throw StateError('project is not registered on $host');
                    }
                    final branches = host == 'local'
                        ? ['main']
                        : ['remote-main'];
                    return ProjectBranchCatalog(
                      projectId: project.id,
                      hostId: host,
                      branches: branches,
                      localBranches: branches.toSet(),
                    );
                  },
                  checkBranchExists: (_, _) async => false,
                  workspaceBranches: (_) => const <String>{},
                  parentWorkspaces: const <Workspace>[],
                  generateIdentity: ({
                    required operationId,
                    required projectId,
                    required prompt,
                    required autoAssignSection,
                  }) async => throw UnimplementedError(),
                  cancelGeneration: (_) async {},
                  createWorkspace: ({
                    required project,
                    required sourceBranch,
                    required newBranchName,
                    required name,
                    parentWorkspaceId,
                    hostId,
                    issueUrl,
                  }) async => throw UnimplementedError(),
                  launchAgent: ({
                    required workspaceId,
                    required profileId,
                    required prompt,
                    required clientMutationId,
                    required requireIdempotency,
                  }) async => throw UnimplementedError(),
                  supportsIdempotentAgentLaunch: () async => true,
                  enqueuePrompt: (request) {
                    requests.add(request);
                    return Future<void>.value();
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
