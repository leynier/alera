import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    group('WelcomeDashboard goldens', () {
      goldenTest(
        'renders populated desktop dashboard',
        fileName: 'welcome_dashboard_populated_desktop',
        constraints: const BoxConstraints.tightFor(width: 980, height: 720),
        builder: () => _GoldenDashboardFrame(state: _populatedState()),
      );

      goldenTest(
        'renders empty compact dashboard',
        fileName: 'welcome_dashboard_empty_compact',
        constraints: const BoxConstraints.tightFor(width: 390, height: 760),
        builder: () => const _GoldenDashboardFrame(
          state: WorkbenchState(bootstrapped: true),
        ),
      );
    });
  });
}

class _GoldenDashboardFrame extends StatelessWidget {
  const _GoldenDashboardFrame({required this.state});

  final WorkbenchState state;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        workbenchControllerProvider.overrideWith(
          (ref) => _GoldenWorkbenchController(state),
        ),
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(
            _GoldenSettingsRepository(),
            loadOnCreate: false,
          ),
        ),
      ],
      child: const WelcomeDashboard(),
    );
  }
}

WorkbenchState _populatedState() {
  final now = DateTime.utc(2026, 5, 25);
  final project = Project(
    id: 'project-alera',
    name: 'Alera',
    repoPath: '/projects/alera',
    createdAt: now,
    updatedAt: now,
  );
  final mainWorkspace = Workspace(
    id: 'workspace-main',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
  final linkedWorkspace = Workspace(
    id: 'workspace-terminal-refactor',
    projectId: project.id,
    name: 'Terminal refactor',
    branch: 'feature/terminal-refactor',
    path: '/projects/.alera/workspaces/alera/terminal-refactor',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
    sourceBranch: 'main',
  );

  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[mainWorkspace, linkedWorkspace],
    },
    activeProjectId: project.id,
    bootstrapped: true,
  );
}

class _GoldenWorkbenchController extends WorkbenchController {
  _GoldenWorkbenchController(WorkbenchState seed)
    : super(
        projectsService: ProjectsService(
          projectService: ProjectService(_UnusedProcessRunner()),
          projectRepository: _UnusedProjectRepository(),
        ),
        repository: _UnusedWorkbenchRepository(),
        workspaceService: WorkspaceService(
          repository: _UnusedWorkbenchRepository(),
          projectService: ProjectService(_UnusedProcessRunner()),
          processRunner: _UnusedProcessRunner(),
        ),
        workspaceTabService: WorkspaceTabService(
          repository: _UnusedWorkbenchRepository(),
        ),
      ) {
    state = seed;
  }

  @override
  Future<void> bootstrap() async {}
}

class _GoldenSettingsRepository implements SettingsRepository {
  @override
  Future<AleraSettings> load() async => AleraSettings.defaults;

  @override
  Future<void> save(AleraSettings settings) async {}
}

class _UnusedProjectRepository implements ProjectRepository {
  @override
  Future<Project> add(Project project) async => project;

  @override
  Future<List<Project>> listAll() async => const <Project>[];

  @override
  Future<void> remove(String projectId) async {}

  @override
  Future<Project> update(Project project) async => project;

  @override
  Stream<List<Project>> watchAll() => const Stream<List<Project>>.empty();
}

class _UnusedWorkbenchRepository implements WorkbenchRepository {
  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async => null;

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async =>
      null;

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async => null;

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(
    String workspaceId,
  ) async => const <WorkspaceTabRecord>[];

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async =>
      const <Workspace>[];

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {}

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {}

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {}

  @override
  Future<void> removeWorkspaceTab(String tabId) async {}

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {}

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async =>
      layout;

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async => workspace;

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async =>
      tab;

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) =>
      const Stream<List<WorkspaceTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}

class _UnusedProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 1, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError('Golden tests do not start processes.');
  }
}
