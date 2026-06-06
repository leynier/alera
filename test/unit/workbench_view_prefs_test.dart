import 'package:dart_mappable/dart_mappable.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
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
      expect(WorkbenchViewPrefs.defaults.rightSidebarVisible, isTrue);
      expect(WorkbenchViewPrefs.defaults.rightSidebarWidth, 280);
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
        groupBy: WorkbenchGroupBy.none,
        projectSort: WorkbenchSortBy.recent,
        workspaceSort: WorkbenchSortBy.recent,
        selectedProjectIds: <String>{'p1', 'p2'},
        collapsedProjectIds: <String>{'p3'},
        expandedWorkspaceIds: <String>{'w1'},
        rightSidebarVisible: false,
        rightSidebarWidth: 360,
        activeContextPanelTab: WorkbenchContextPanelTab.explorer,
        explorerMode: WorkspaceExplorerMode.showAll,
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
      expect(restored.rightSidebarVisible, isFalse);
      expect(restored.rightSidebarWidth, 360);
      expect(restored.activeContextPanelTab, WorkbenchContextPanelTab.explorer);
      expect(restored.explorerMode, WorkspaceExplorerMode.showAll);
    });

    test('fromJson requires the current schema', () {
      expect(
        () => WorkbenchViewPrefs.fromJson(<String, Object?>{}),
        throwsA(isA<MapperException>()),
      );
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
        groupBy: WorkbenchGroupBy.none,
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
