import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_providers.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_page.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'run_board_fixtures.dart';

WorkbenchState boardWorkbenchState() {
  final now = DateTime.utc(2026, 8, 30);
  final projects = [
    for (final id in ['1', '2'])
      Project(
        id: 'project-$id',
        name: id == '1' ? 'Alera' : 'Other Project',
        repoPath: '/project/$id',
        createdAt: now,
        updatedAt: now,
      ),
  ];
  final workspaces = [
    for (final id in ['1', '2'])
      Workspace(
        id: 'ws-$id',
        projectId: 'project-$id',
        name: id == '1' ? 'Workflow Delivery' : 'Current Workspace',
        path: '/project/$id',
        branch: 'main',
        createdAt: now,
        updatedAt: now,
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      ),
  ];
  return WorkbenchState(
    projects: projects,
    workspacesByProject: {
      for (final workspace in workspaces) workspace.projectId: [workspace],
    },
    tabsByWorkspace: {
      'ws-1': [
        WorkspaceTabRecord(
          id: 'session-1',
          workspaceId: 'ws-1',
          title: 'Implementation',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    },
    activeProjectId: 'project-2',
    activeWorkspaceId: 'ws-2',
    bootstrapped: true,
  );
}

class BoardTestWorkbench extends WorkbenchController {
  BoardTestWorkbench({this.seed});
  final WorkbenchState? seed;
  final actions = <String>[];
  @override
  WorkbenchState build() => seed ?? boardWorkbenchState();
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
    bool preview = false,
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
}

ProviderContainer boardContainer(
  BoardTestRepository repository, {
  BoardTestWorkbench? workbench,
}) => ProviderContainer(
  overrides: [
    runBoardRepositoryProvider.overrideWithValue(repository),
    appForegroundProvider.overrideWithValue(const AlwaysForeground()),
    workbenchControllerProvider.overrideWith(
      () => workbench ?? BoardTestWorkbench(),
    ),
  ],
);

class BoardTestApp extends StatelessWidget {
  const BoardTestApp({super.key, required this.container, this.scale = 1});
  final ProviderContainer container;
  final double scale;
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAleraDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) =>
              ref.watch(runBoardNavigationProvider).visible
              ? const RunBoardPage()
              : Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.read(runBoardNavigationProvider.notifier).open(),
                    child: const Text('Open Run Board'),
                  ),
                ),
        ),
      ),
    ),
  );
}
