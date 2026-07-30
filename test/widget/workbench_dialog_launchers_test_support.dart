// Shared harness for the workbench dialog launcher widget suites.
import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

Future<void> pumpFlowHarness(
  WidgetTester tester, {
  required DialogLaunchersTestController controller,
  required Future<void> Function(BuildContext context, WidgetRef ref) onPressed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workbenchControllerProvider.overrideWith(() => controller),
        agentProfilesProvider.overrideWith(
          () => DialogLaunchersAgentProfiles(),
        ),
        gitBackendProvider.overrideWithValue(FakeGitBackend()),
        settingsControllerProvider.overrideWith(
          () => DialogLaunchersSettingsController(AleraSettings.defaults),
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

class DialogLaunchersAgentProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const <AgentProfile>[];
}

Project buildProject(
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

Workspace buildWorkspace({
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

class DialogLaunchersTestController extends WorkbenchController {
  DialogLaunchersTestController(this._seed);

  final WorkbenchState _seed;

  String? addedLocalPath;
  String? addedLocalName;
  Exception? addLocalError;
  Completer<Project>? cloneCompleter;
  ({String gitUrl, String destinationPath, String? name})? clonedProjectCall;
  List<String> sourceBranches = const <String>['main'];
  Exception? createWorkspaceError;
  String? parentLinkError;
  WorktreeSetupReport setupReport = WorktreeSetupReport.empty;
  ({
    Project project,
    String sourceBranch,
    String newBranchName,
    bool reuseExistingBranch,
    String? name,
    String? parentWorkspaceId,
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
    return buildProject('project-local', name ?? 'notes');
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
    return buildProject('project-clone', name ?? 'clone');
  }

  @override
  Future<List<String>> listSourceBranches(Project project) async {
    return sourceBranches;
  }

  @override
  Future<WorkspaceCreationResult> createWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
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
      parentWorkspaceId: parentWorkspaceId,
    );
    return WorkspaceCreationResult(
      workspace: buildWorkspace(
        id: 'workspace-created',
        projectId: project.id,
        name: name ?? newBranchName,
      ),
      setupReport: setupReport,
      parentLinkError: parentLinkError,
    );
  }
}

class DialogLaunchersSettingsController extends SettingsController {
  DialogLaunchersSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}
