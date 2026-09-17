import 'package:dart_mappable/dart_mappable.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkbenchViewPrefs', () {
    test('defaults match the documented values', () {
      expect(WorkbenchViewPrefs.defaults.groupBy, WorkbenchGroupBy.project);
      expect(WorkbenchViewPrefs.defaults.projectSort, WorkbenchSortBy.name);
      expect(WorkbenchViewPrefs.defaults.workspaceSort, WorkbenchSortBy.name);
      expect(WorkbenchViewPrefs.defaults.selectedProjectIds, isEmpty);
      expect(WorkbenchViewPrefs.defaults.collapsedProjectIds, isEmpty);
      expect(WorkbenchViewPrefs.defaults.expandedWorkspaceIds, isEmpty);
      expect(WorkbenchViewPrefs.defaults.selectedTagIds, isEmpty);
      expect(WorkbenchViewPrefs.defaults.collapsedParentWorkspaceIds, isEmpty);
      expect(WorkbenchViewPrefs.defaults.showPinnedWorkspacesBelow, isTrue);
      expect(WorkbenchViewPrefs.defaults.showActiveWorkspacesOnly, isFalse);
      expect(
        WorkbenchViewPrefs.defaults.sourceControlRootByWorkspaceId,
        isEmpty,
      );
      expect(
        WorkbenchViewPrefs.defaults.rightSidebarWidthByWorkspaceId,
        isEmpty,
      );
      expect(WorkbenchViewPrefs.defaults.rightSidebarVisible, isTrue);
      expect(WorkbenchViewPrefs.defaults.rightSidebarWidth, 280);
      expect(
        WorkbenchViewPrefs.defaults.sidebarWidth,
        AleraTokens.sidebarDefaultWidth,
      );
      expect(
        WorkbenchViewPrefs.defaults.activeContextPanelTab,
        WorkbenchContextPanelTab.explorer,
      );
      expect(
        WorkbenchViewPrefs.defaults.explorerMode,
        WorkspaceExplorerMode.hideIgnored,
      );
    });

    test('round-trips through json', () {
      const prefs = WorkbenchViewPrefs(
        groupBy: .none,
        projectSort: .recent,
        workspaceSort: .recent,
        selectedProjectIds: <String>{'p1', 'p2'},
        collapsedProjectIds: <String>{'p3'},
        expandedWorkspaceIds: <String>{'w1'},
        selectedTagIds: <String>{'tag-1'},
        collapsedParentWorkspaceIds: <String>{'w-parent'},
        showPinnedWorkspacesBelow: false,
        showActiveWorkspacesOnly: true,
        sourceControlRootByWorkspaceId: <String, String>{
          'w-folder': 'packages/app',
        },
        rightSidebarWidthByWorkspaceId: <String, double>{'w-folder': 400},
        rightSidebarVisible: false,
        rightSidebarWidth: 360,
        sidebarWidth: 360,
        activeContextPanelTab: .explorer,
        explorerMode: .showAll,
      );
      final restored = WorkbenchViewPrefs.fromJson(
        Map<String, Object?>.from(prefs.toMap()),
      );
      expect(restored.groupBy, WorkbenchGroupBy.none);
      expect(restored.projectSort, WorkbenchSortBy.recent);
      expect(restored.workspaceSort, WorkbenchSortBy.recent);
      expect(restored.selectedProjectIds, <String>{'p1', 'p2'});
      expect(restored.collapsedProjectIds, <String>{'p3'});
      expect(restored.expandedWorkspaceIds, <String>{'w1'});
      expect(restored.selectedTagIds, <String>{'tag-1'});
      expect(restored.collapsedParentWorkspaceIds, <String>{'w-parent'});
      expect(restored.showPinnedWorkspacesBelow, isFalse);
      expect(restored.showActiveWorkspacesOnly, isTrue);
      expect(restored.sourceControlRootByWorkspaceId, <String, String>{
        'w-folder': 'packages/app',
      });
      expect(restored.rightSidebarWidthByWorkspaceId, <String, double>{
        'w-folder': 400,
      });
      expect(restored.rightSidebarVisible, isFalse);
      expect(restored.rightSidebarWidth, 360);
      expect(restored.sidebarWidth, 360);
      expect(restored.activeContextPanelTab, WorkbenchContextPanelTab.explorer);
      expect(restored.explorerMode, WorkspaceExplorerMode.showAll);
    });

    test('fromJson requires the current schema', () {
      expect(
        () => WorkbenchViewPrefs.fromJson(<String, Object?>{}),
        throwsA(isA<MapperException>()),
      );
    });

    test('fromJson maps retired Agent Canvas prefs to explorer', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <String>[],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
        'activeContextPanelTab': 'agentCanvas',
      });
      expect(restored.activeContextPanelTab, WorkbenchContextPanelTab.explorer);
    });

    test('fromJson rejects unknown enum names', () {
      expect(
        () => WorkbenchViewPrefs.fromJson(<String, Object?>{
          'groupBy': 'unknown',
          'projectSort': 'also-unknown',
          'workspaceSort': 'recent',
          'selectedProjectIds': <String>[],
          'collapsedProjectIds': <String>[],
          'expandedWorkspaceIds': <String>[],
        }),
        throwsA(isA<MapperException>()),
      );
    });

    test('fromJson tolerates persisted prefs without the new fields', () {
      // JSON persisted before selectedTagIds/collapsedParentWorkspaceIds and
      // the activity sort existed must keep decoding.
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'recent',
        'selectedProjectIds': <String>['p1'],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
      });

      expect(restored.selectedTagIds, isEmpty);
      expect(restored.collapsedParentWorkspaceIds, isEmpty);
      expect(restored.workspaceSort, WorkbenchSortBy.recent);
      expect(restored.workspaceKindFilter, WorkspaceKindFilter.all);
      expect(restored.showPinnedWorkspacesBelow, isTrue);
      expect(restored.showActiveWorkspacesOnly, isFalse);
      expect(restored.gitDiffGroupMode, GitDiffGroupMode.byArea);
      expect(restored.rightSidebarWidthByWorkspaceId, isEmpty);
    });

    test(
      'fromJson prefers the former panel width when both legacy widths exist',
      () {
        final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
          'groupBy': 'project',
          'projectSort': 'name',
          'workspaceSort': 'name',
          'selectedProjectIds': <String>[],
          'collapsedProjectIds': <String>[],
          'expandedWorkspaceIds': <String>[],
          'desktopLayout': 'classic',
          'rightSidebarWidth': 280,
          'experimentalRightSidebarWidth': 400,
        });

        expect(restored.rightSidebarWidth, 400);
      },
    );

    test('fromJson maps retired experimental panel keys', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <String>[],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
        'experimentalPanels': <String, Object?>{
          'w-1': const WorkspacePanel(primaryTabId: 'primary').toMap(),
        },
        'experimentalNewWorkspaceTools': <Object?>[
          'explorer',
          'unknown',
          'explorer',
          'search',
        ],
      });

      expect(restored.workspacePanels.keys, <String>['w-1']);
      expect(restored.workspacePanels['w-1']?.primaryTabId, 'primary');
      expect(restored.newWorkspaceTools, <WorkspaceTool>[
        WorkspaceTool.explorer,
        WorkspaceTool.search,
      ]);
    });

    test('fromJson keeps a valid new-workspace tools list unchanged', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <String>[],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
        'newWorkspaceTools': <String>['search', 'pullRequest'],
      });

      expect(restored.newWorkspaceTools, <WorkspaceTool>[
        WorkspaceTool.search,
        WorkspaceTool.pullRequest,
      ]);
    });

    test('fromJson drops non-numeric right-sidebar width entries', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <String>[],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
        'rightSidebarWidth': 280,
        'rightSidebarWidthByWorkspaceId': <String, Object?>{
          'w-wide': 400,
          'w-bad': 'wide',
        },
      });

      expect(restored.rightSidebarWidthByWorkspaceId, <String, double>{
        'w-wide': 400,
      });
    });

    test('fromJson drops right-sidebar widths that match the fallback', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <String>[],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
        'rightSidebarWidth': 280,
        'rightSidebarWidthByWorkspaceId': <String, Object?>{
          'w-default': 280,
          'w-wide': 400,
        },
      });

      expect(restored.rightSidebarWidthByWorkspaceId, <String, double>{
        'w-wide': 400,
      });
    });

    test('rightSidebarWidthFor prefers the workspace override', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        rightSidebarWidth: 280,
        rightSidebarWidthByWorkspaceId: const <String, double>{'w-1': 400},
      );

      expect(prefs.rightSidebarWidthFor(null), 280);
      expect(prefs.rightSidebarWidthFor('missing'), 280);
      expect(prefs.rightSidebarWidthFor('w-1'), 400);
      expect(prefs.rightSidebarWidthFor('missing', fallback: 320), 320);
      expect(prefs.rightSidebarWidthFor('w-1', fallback: 320), 400);
    });

    test('round-trips the git diff group mode', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        gitDiffGroupMode: .unified,
      );
      final restored = WorkbenchViewPrefs.fromJson(
        Map<String, Object?>.from(prefs.toMap()),
      );
      expect(restored.gitDiffGroupMode, GitDiffGroupMode.unified);
    });

    test('drops retired workspace kind filters when loading preferences', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        workspaceKindFilter: .nonDefaultOnly,
      );
      final restored = WorkbenchViewPrefs.fromJson(
        Map<String, Object?>.from(prefs.toMap()),
      );
      expect(restored.workspaceKindFilter, WorkspaceKindFilter.all);
    });

    test('fromJson decodes the activity sort value', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'activity',
        'workspaceSort': 'activity',
        'selectedProjectIds': <String>[],
        'collapsedProjectIds': <String>[],
        'expandedWorkspaceIds': <String>[],
      });

      expect(restored.projectSort, WorkbenchSortBy.activity);
      expect(restored.workspaceSort, WorkbenchSortBy.activity);
    });

    test('fromJson applies mapper conversions inside id collections', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <Object?>['p1', 42],
        'collapsedProjectIds': <String>['p3'],
        'expandedWorkspaceIds': <String>['w1'],
      });

      expect(restored.selectedProjectIds, <String>{'p1', '42'});
      expect(restored.collapsedProjectIds, <String>{'p3'});
      expect(restored.expandedWorkspaceIds, <String>{'w1'});
    });

    test('copyWith updates individual fields', () {
      const prefs = WorkbenchViewPrefs.defaults;
      final updated = prefs.copyWith(
        groupBy: .none,
        selectedProjectIds: <String>{'x'},
      );
      expect(updated.groupBy, WorkbenchGroupBy.none);
      expect(updated.selectedProjectIds, <String>{'x'});
      // Untouched fields stay at the original values.
      expect(updated.projectSort, WorkbenchSortBy.name);
      expect(updated.workspaceSort, WorkbenchSortBy.name);
      expect(updated.collapsedProjectIds, isEmpty);
      expect(updated.rightSidebarVisible, isTrue);
    });
  });
}
