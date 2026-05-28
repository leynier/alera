import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_view_prefs.mapper.dart';

@MappableEnum()
enum WorkbenchGroupBy { none, project }

@MappableEnum()
enum WorkbenchSortBy { name, recent }

@MappableClass()
class WorkbenchViewPrefs with WorkbenchViewPrefsMappable {
  const WorkbenchViewPrefs({
    required this.groupBy,
    required this.projectSort,
    required this.workspaceSort,
    required this.selectedProjectIds,
    required this.collapsedProjectIds,
    required this.expandedWorkspaceIds,
  });

  final WorkbenchGroupBy groupBy;
  final WorkbenchSortBy projectSort;
  final WorkbenchSortBy workspaceSort;

  /// Projects the user has explicitly added to the visibility filter. When the
  /// set is empty the sidebar shows every project; when non-empty it shows
  /// only the listed ones (positive selection, Orca-style).
  final Set<String> selectedProjectIds;
  final Set<String> collapsedProjectIds;

  /// Workspaces whose sidebar agent-run list is currently expanded.
  /// Activating a workspace adds it to this set so agent runs are visible by
  /// default; the per-row chevron lets the user toggle membership without
  /// changing the active selection.
  final Set<String> expandedWorkspaceIds;

  static const WorkbenchViewPrefs defaults = WorkbenchViewPrefs(
    groupBy: WorkbenchGroupBy.project,
    projectSort: WorkbenchSortBy.name,
    workspaceSort: WorkbenchSortBy.name,
    selectedProjectIds: <String>{},
    collapsedProjectIds: <String>{},
    expandedWorkspaceIds: <String>{},
  );

  factory WorkbenchViewPrefs.fromJson(Map<String, Object?> json) =>
      WorkbenchViewPrefsMapper.fromMap(Map<String, dynamic>.from(json));
}
