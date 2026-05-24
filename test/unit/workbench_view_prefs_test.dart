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
    });

    test('round-trips through json', () {
      const prefs = WorkbenchViewPrefs(
        groupBy: WorkbenchGroupBy.none,
        projectSort: WorkbenchSortBy.recent,
        workspaceSort: WorkbenchSortBy.recent,
        selectedProjectIds: <String>{'p1', 'p2'},
        collapsedProjectIds: <String>{'p3'},
        expandedWorkspaceIds: <String>{'w1'},
      );
      final restored = WorkbenchViewPrefs.fromJson(prefs.toJson());
      expect(restored.groupBy, WorkbenchGroupBy.none);
      expect(restored.projectSort, WorkbenchSortBy.recent);
      expect(restored.workspaceSort, WorkbenchSortBy.recent);
      expect(restored.selectedProjectIds, <String>{'p1', 'p2'});
      expect(restored.collapsedProjectIds, <String>{'p3'});
      expect(restored.expandedWorkspaceIds, <String>{'w1'});
    });

    test('fromJson falls back to defaults on empty input', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{});
      expect(restored.groupBy, WorkbenchGroupBy.project);
      expect(restored.projectSort, WorkbenchSortBy.name);
      expect(restored.workspaceSort, WorkbenchSortBy.name);
      expect(restored.selectedProjectIds, isEmpty);
      expect(restored.collapsedProjectIds, isEmpty);
      expect(restored.expandedWorkspaceIds, isEmpty);
    });

    test('fromJson ignores unknown enum names', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'unknown',
        'projectSort': 'also-unknown',
        'workspaceSort': 'recent',
      });
      expect(restored.groupBy, WorkbenchGroupBy.project);
      expect(restored.projectSort, WorkbenchSortBy.name);
      expect(restored.workspaceSort, WorkbenchSortBy.recent);
    });

    test('fromJson skips non-string entries in id lists', () {
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'selectedProjectIds': <Object?>['p1', 42, '', null, 'p2'],
        'collapsedProjectIds': <Object?>['p3'],
        'expandedWorkspaceIds': <Object?>['w1', null, 0, 'w2'],
      });
      expect(restored.selectedProjectIds, <String>{'p1', 'p2'});
      expect(restored.collapsedProjectIds, <String>{'p3'});
      expect(restored.expandedWorkspaceIds, <String>{'w1', 'w2'});
    });

    test('fromJson discards legacy hiddenProjectIds (semantics inverted)', () {
      // Older builds stored a negative filter under "hiddenProjectIds". Loading
      // that as a positive filter would silently hide unrelated projects, so
      // we drop it and reset to the default "all visible" view.
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'hiddenProjectIds': <Object?>['p-legacy-1', 'p-legacy-2'],
      });
      expect(restored.selectedProjectIds, isEmpty);
    });

    test('fromJson discards legacy terminalsCollapsedWorkspaceIds', () {
      // Older builds tracked "which workspace terminals are hidden". The new
      // model is the inverse, so legacy values are ignored on load.
      final restored = WorkbenchViewPrefs.fromJson(<String, Object?>{
        'groupBy': 'project',
        'projectSort': 'name',
        'workspaceSort': 'name',
        'terminalsCollapsedWorkspaceIds': <Object?>['w-legacy'],
      });
      expect(restored.expandedWorkspaceIds, isEmpty);
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
    });
  });
}
