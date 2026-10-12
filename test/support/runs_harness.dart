import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_page.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/infra/recipe_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'runs_fake_repository.dart';
import 'runs_fixtures.dart';

WorkbenchState runsWorkbenchState() {
  final now = DateTime.utc(2026, 8, 30);
  final projects = <Project>[
    for (final id in <String>['1', '2'])
      Project(
        id: 'project-$id',
        name: id == '1' ? 'alera' : 'educup',
        repoPath: '/project/$id',
        createdAt: now,
        updatedAt: now,
      ),
  ];
  final workspaces = <Workspace>[
    for (final id in <String>['1', '2'])
      Workspace(
        id: 'ws-$id',
        projectId: 'project-$id',
        name: id == '1' ? 'feature-oauth' : 'ci-migration',
        path: '/project/$id',
        branch: 'main',
        createdAt: now,
        updatedAt: now,
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      ),
  ];
  WorkspaceTabRecord tab(String id, String workspaceId, String title) =>
      WorkspaceTabRecord(
        id: id,
        workspaceId: workspaceId,
        title: title,
        createdAt: now,
        updatedAt: now,
      );
  return WorkbenchState(
    projects: projects,
    workspacesByProject: <String, List<Workspace>>{
      for (final project in projects)
        project.id: workspaces
            .where((workspace) => workspace.projectId == project.id)
            .toList(),
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      'ws-1': <WorkspaceTabRecord>[
        tab('coordinator-1', 'ws-1', 'Coordinator'),
        tab('w-3', 'ws-1', 'implement-github'),
      ],
    },
    activeProjectId: 'project-2',
    activeWorkspaceId: 'ws-2',
    bootstrapped: true,
  );
}

class RunsTestWorkbench extends WorkbenchController {
  RunsTestWorkbench({this.seed});
  final WorkbenchState? seed;
  final List<String> actions = <String>[];
  @override
  WorkbenchState build() => seed ?? runsWorkbenchState();
  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    actions.add('workspace:${workspace.id}');
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
    );
  }

  @override
  Future<void> selectWorkspaceTab({
    required String workspaceId,
    required String tabId,
  }) async {
    actions.add('terminal:$tabId');
  }

  @override
  Future<WorkspaceTabRecord> openGitDiffTab({
    required Workspace workspace,
    String? relativePath,
    GitChangeArea? area,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
    bool oppositePanel = false,
  }) async {
    actions.add('diff:${workspace.id}');
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'diff',
      workspaceId: workspace.id,
      title: 'Diff',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceTabKind.gitDiff,
    );
  }

  @override
  Future<WorkspaceTabRecord> openGitCommitDiffTab({
    required Workspace workspace,
    String? relativePath,
    String? oldPath,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    required String commitOid,
    String? parentOid,
    required String compareRef,
    String? subject,
    String? message,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
    bool oppositePanel = false,
  }) async {
    actions.add('commitDiff:${workspace.id}:$parentOid..$commitOid:$subject');
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'commit-diff',
      workspaceId: workspace.id,
      title: 'Diff',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceTabKind.gitDiff,
    );
  }
}

class RunsTestAgentProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => <AgentProfile>[
    AgentProfile(
      id: 'codex-sol',
      name: 'Codex Sol',
      agentType: 'codex',
      command: 'codex',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    AgentProfile(
      id: 'cursor',
      name: 'Cursor',
      agentType: 'cursor',
      command: 'cursor-agent',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];
}

ProviderContainer runsContainer(
  FakeRunRepository repository, {
  RunsTestWorkbench? workbench,
  TerminalRuntime? terminalRuntime,
  RecipeRepository? recipes,
}) => ProviderContainer(
  overrides: [
    runRepositoryProvider.overrideWithValue(repository),
    if (recipes != null) recipeRepositoryProvider.overrideWithValue(recipes),
    runClockProvider.overrideWithValue(() => runsTestNow),
    appForegroundProvider.overrideWithValue(const AlwaysForeground()),
    agentProfilesProvider.overrideWith(RunsTestAgentProfiles.new),
    terminalRuntimeProvider.overrideWith((ref) {
      final runtime = terminalRuntime ?? XtermTerminalRuntime();
      if (terminalRuntime == null) ref.onDispose(runtime.dispose);
      return runtime;
    }),
    workbenchControllerProvider.overrideWith(
      () => workbench ?? RunsTestWorkbench(),
    ),
    // Questions and automations would reach for a real runtime.
    activityAttentionProvider.overrideWithValue(const ActivityAttention()),
  ],
);

/// Activity inside a MaterialApp, opened on Runs by the test.
class RunsTestApp extends StatelessWidget {
  const RunsTestApp({super.key, required this.container, this.scale = 1});
  final ProviderContainer container;
  final double scale;
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAleraDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) =>
              ref.watch(activityNavigationProvider).visible
              ? const ActivityPage()
              : Center(
                  child: TextButton(
                    onPressed: () => ref
                        .read(activityNavigationProvider.notifier)
                        .open(ActivitySection.runs),
                    child: const Text('Open Activity'),
                  ),
                ),
        ),
      ),
    ),
  );
}
