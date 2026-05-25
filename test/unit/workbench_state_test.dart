import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkbenchState', () {
    final now = DateTime.utc(2026, 5, 25, 12);

    Project project(String id, String name) {
      return Project(
        id: id,
        name: name,
        repoPath: '/repo/$id',
        createdAt: now,
        updatedAt: now,
      );
    }

    Workspace workspace({
      required String id,
      required String projectId,
      required String name,
      String? branch,
      String? sourceBranch,
    }) {
      return Workspace(
        id: id,
        projectId: projectId,
        name: name,
        branch: branch,
        sourceBranch: sourceBranch,
        path: '/repo/$projectId/$id',
        createdAt: now,
        updatedAt: now,
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );
    }

    WorkspaceTabRecord tab(String id, String workspaceId) {
      return WorkspaceTabRecord(
        id: id,
        workspaceId: workspaceId,
        title: id,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('resolves active project, workspace, tab, and layout', () {
      final projectA = project('project-a', 'Alera');
      final workspaceA = workspace(
        id: 'workspace-a',
        projectId: projectA.id,
        name: 'Main',
        branch: 'main',
      );
      final firstTab = tab('tab-1', workspaceA.id);
      final secondTab = tab('tab-2', workspaceA.id);
      final layout = WorkbenchLayout.single(
        workspaceId: workspaceA.id,
        tabIds: <String>[firstTab.id, secondTab.id],
      );
      final state = WorkbenchState(
        projects: <Project>[projectA],
        workspacesByProject: <String, List<Workspace>>{
          projectA.id: <Workspace>[workspaceA],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspaceA.id: <WorkspaceTabRecord>[firstTab, secondTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{workspaceA.id: layout},
        activeProjectId: projectA.id,
        activeWorkspaceId: workspaceA.id,
        activeTabIdByWorkspace: <String, String>{workspaceA.id: firstTab.id},
      );

      expect(state.activeProject, projectA);
      expect(state.activeWorkspace, workspaceA);
      expect(state.activeLayout, layout);
      expect(state.activeWorkspaceTab, secondTab);
    });

    test(
      'returns expanded projects and ordered tabs for an existing group',
      () {
        final projectA = project('project-a', 'Alera');
        final projectB = project('project-b', 'Orca');
        final workspaceA = workspace(
          id: 'workspace-a',
          projectId: projectA.id,
          name: 'Main',
        );
        final firstTab = tab('tab-1', workspaceA.id);
        final secondTab = tab('tab-2', workspaceA.id);
        final groupId = WorkbenchLayout.defaultGroupId(workspaceA.id);
        final layout = WorkbenchLayout.single(
          workspaceId: workspaceA.id,
          tabIds: <String>[firstTab.id, 'missing-tab', secondTab.id],
        );
        final state = WorkbenchState(
          projects: <Project>[projectA, projectB],
          workspacesByProject: <String, List<Workspace>>{
            projectA.id: <Workspace>[workspaceA],
          },
          tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
            workspaceA.id: <WorkspaceTabRecord>[firstTab, secondTab],
          },
          layoutByWorkspace: <String, WorkbenchLayout>{workspaceA.id: layout},
          viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
            collapsedProjectIds: <String>{projectA.id},
          ),
        );

        expect(state.expandedProjectIds, <String>{projectB.id});
        expect(state.tabsForGroup(workspaceA.id, groupId), <WorkspaceTabRecord>[
          firstTab,
          secondTab,
        ]);
        expect(state.tabsForGroup(workspaceA.id, 'missing-group'), isEmpty);
      },
    );

    test('matches workspaces by name, branch, and source branch', () {
      final projectA = project('project-a', 'Alera');
      final workspaceA = workspace(
        id: 'workspace-a',
        projectId: projectA.id,
        name: 'Main checkout',
        branch: 'main',
        sourceBranch: 'feature/api',
      );
      final state = WorkbenchState(
        projects: <Project>[projectA],
        workspacesByProject: <String, List<Workspace>>{
          projectA.id: <Workspace>[workspaceA],
        },
        searchQuery: ' FeAtUrE ',
      );

      expect(state.hasSearchQuery(), isTrue);
      expect(state.workspaceMatches(workspaceA), isTrue);
      expect(
        state.workspaceMatches(
          workspace(
            id: 'workspace-b',
            projectId: projectA.id,
            name: 'Docs',
            branch: 'docs',
          ),
        ),
        isFalse,
      );
    });

    test('groups search results by project and skips blank queries', () {
      final projectA = project('project-a', 'Alera');
      final projectB = project('project-b', 'Orca');
      final workspaceA = workspace(
        id: 'workspace-a',
        projectId: projectA.id,
        name: 'Terminal API',
      );
      final workspaceB = workspace(
        id: 'workspace-b',
        projectId: projectB.id,
        name: 'Landing',
      );
      final searchingState = WorkbenchState(
        projects: <Project>[projectA, projectB],
        workspacesByProject: <String, List<Workspace>>{
          projectA.id: <Workspace>[workspaceA],
          projectB.id: <Workspace>[workspaceB],
        },
        searchQuery: 'alera',
      );
      final blankState = searchingState.copyWith(searchQuery: '   ');

      final results = searchingState.searchResults();

      expect(results, hasLength(1));
      expect(results.single.project, projectA);
      expect(results.single.workspaces, <Workspace>[workspaceA]);
      expect(blankState.searchResults(), isEmpty);
    });
  });
}
