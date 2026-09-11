// Shared harness for the workbench dialog launcher widget suites.
import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/app_navigation.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/projects/domain/project_clone_job.dart';
import 'package:alera/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/presentation/background_setup_job_host.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
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
        backgroundSetupJobsProvider.overrideWith(
          DialogLaunchersBackgroundSetupJobs.new,
        ),
        agentProfilesProvider.overrideWith(
          () => DialogLaunchersAgentProfiles(),
        ),
        gitBackendProvider.overrideWithValue(FakeGitBackend()),
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(_HarnessRuntimeHostClient()),
        ),
        settingsControllerProvider.overrideWith(
          () => DialogLaunchersSettingsController(.defaults),
        ),
      ],
      child: MaterialApp(
        navigatorKey: aleraNavigatorKey,
        home: Scaffold(
          body: Center(
            child: Consumer(
              builder: (context, ref, _) {
                return FilledButton(
                  onPressed: () => onPressed(context, ref),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
        builder: (context, child) {
          return Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              const BackgroundSetupJobHost(),
              const AleraToastHost(),
            ],
          );
        },
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
    kind: .linked,
    status: .active,
    sourceBranch: 'main',
  );
}

class DialogLaunchersTestController(final WorkbenchState _seed)
    extends WorkbenchController {
  String? addedLocalPath;
  String? addedLocalName;
  Exception? addLocalError;
  Completer<Project>? cloneCompleter;
  Completer<WorkspaceCreationResult>? createCompleter;
  ({String gitUrl, String destinationPath, String? name})? clonedProjectCall;
  List<String> sourceBranches = const <String>['main'];
  Exception? createWorkspaceError;
  String? parentLinkError;
  WorktreeSetupReport setupReport = .empty;
  ({
    Project project,
    String sourceBranch,
    String newBranchName,
    bool reuseExistingBranch,
    String? name,
    String? parentWorkspaceId,
    String? hostId,
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
    String? hostId,
  }) async {
    if (createWorkspaceError case final Exception error) {
      throw error;
    }
    if (createCompleter case final Completer<WorkspaceCreationResult> pending) {
      createdWorkspaceCall = (
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        reuseExistingBranch: reuseExistingBranch,
        name: name,
        parentWorkspaceId: parentWorkspaceId,
        hostId: hostId,
      );
      return pending.future;
    }
    createdWorkspaceCall = (
      project: project,
      sourceBranch: sourceBranch,
      newBranchName: newBranchName,
      reuseExistingBranch: reuseExistingBranch,
      name: name,
      parentWorkspaceId: parentWorkspaceId,
      hostId: hostId,
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

  @override
  Future<ProjectCloneJob> startProjectClone({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) async {
    unawaited(
      cloneProject(
        gitUrl: gitUrl,
        destinationPath: destinationPath,
        name: name,
      ),
    );
    return ProjectCloneJob(
      id: 'clone-job-1',
      source: gitUrl,
      destinationPath: destinationPath,
      status: .running,
      phase: 'cloning',
      updatedAt: DateTime.utc(2026, 5, 25, 12),
      message: 'Cloning repository',
    );
  }

  @override
  Future<List<ProjectCloneJob>> listProjectCloneJobs() async {
    return const <ProjectCloneJob>[];
  }

  @override
  Future<void> cancelProjectClone(String id) async {}

  @override
  Future<void> activateAddedProject(Project project) async {}
}

class DialogLaunchersBackgroundSetupJobs extends BackgroundSetupJobs {
  final Set<String> _inFlightIds = <String>{};

  @override
  BackgroundSetupJobsState build() => const BackgroundSetupJobsState();

  @override
  Future<void>? enqueueManualWorkspace(
    ManualWorkspaceCreateRequest request, {
    String? jobId,
  }) {
    final id = jobId ?? 'manual-job';
    if (!_inFlightIds.add(id)) {
      return null;
    }
    state = state.withJob(
      BackgroundSetupJob(
        id: id,
        kind: .manualWorkspace,
        status: .running,
        title: 'Creating workspace "${request.displayName}"',
        phase: 'Creating workspace',
        snapshot: request,
      ),
    );
    return () async {
      try {
        final result = await ref
            .read(workbenchControllerProvider.notifier)
            .createWorkspace(
              project: request.project,
              sourceBranch: request.sourceBranch,
              newBranchName: request.newBranchName,
              reuseExistingBranch: request.reuseExistingBranch,
              name: request.name,
              parentWorkspaceId: request.parentWorkspaceId,
              hostId: request.hostId,
            );
        state = state.withoutJob(id);
        _toastWorkspace(result);
      } catch (error) {
        state = state.withJob(
          BackgroundSetupJob(
            id: id,
            kind: .manualWorkspace,
            status: .failed,
            title: 'Creating workspace "${request.displayName}"',
            snapshot: request,
            error: error.toString().replaceFirst('Exception: ', ''),
          ),
        );
        rethrow;
      } finally {
        _inFlightIds.remove(id);
      }
    }();
  }

  @override
  Future<void>? enqueuePromptWorkspace(
    PromptWorkspaceCreateRequest request, {
    String? jobId,
  }) {
    return null;
  }

  @override
  Future<void> enqueueProjectClone(
    ProjectCloneRequest request, {
    String? jobId,
  }) async {
    final id = jobId ?? 'clone-job';
    state = state.withJob(
      BackgroundSetupJob(
        id: id,
        kind: .projectClone,
        status: .running,
        title: 'Cloning repository',
        phase: 'Cloning repository',
        snapshot: request,
        canCancel: true,
      ),
    );
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .cloneProject(
            gitUrl: request.gitUrl,
            destinationPath: request.destinationPath,
            name: request.name,
          );
      state = state.withoutJob(id);
      AleraToast.publish(message: 'Project cloned', tone: .success);
    } catch (error) {
      state = state.withJob(
        BackgroundSetupJob(
          id: id,
          kind: .projectClone,
          status: .failed,
          title: 'Cloning repository',
          snapshot: request,
          error: error.toString(),
        ),
      );
    }
  }

  void _toastWorkspace(WorkspaceCreationResult result) {
    if (result.hasSetupWarnings) {
      AleraToast.publish(
        message:
            'Workspace created with setup warnings: ${result.setupReport.summary}',
        tone: .error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (result.hasParentLinkError) {
      AleraToast.publish(
        message: 'Workspace created, but parent link failed',
        tone: .error,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    AleraToast.publish(message: 'Workspace created', tone: .success);
  }
}

Future<void> openManualWorkspaceDialog(WidgetTester tester) async {
  await tester.tap(find.text('Manual'));
  await tester.pumpAndSettle();
}

class DialogLaunchersSettingsController(final AleraSettings _seed)
    extends SettingsController {
  @override
  AleraSettings build() => _seed;
}

class _HarnessRuntimeHostClient implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'sshTarget.list') {
      return const <Object?>[];
    }
    return <String, Object?>{};
  }
}
