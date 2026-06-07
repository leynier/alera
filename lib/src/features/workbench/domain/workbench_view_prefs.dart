import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_view_prefs.mapper.dart';

@MappableEnum()
enum WorkbenchGroupBy { none, project }

@MappableEnum()
enum WorkbenchSortBy { name, recent }

@MappableEnum()
enum WorkbenchContextPanelTab { explorer, search, gitDiff }

@MappableEnum()
enum WorkspaceExplorerMode { hideIgnored, showAll }

@MappableEnum()
enum GitDiffViewMode { tree, flat }

@MappableClass()
class WorkbenchViewPrefs with WorkbenchViewPrefsMappable {
  const WorkbenchViewPrefs({
    required this.groupBy,
    required this.projectSort,
    required this.workspaceSort,
    required this.selectedProjectIds,
    required this.collapsedProjectIds,
    required this.expandedWorkspaceIds,
    this.rightSidebarVisible = true,
    this.rightSidebarWidth = 280,
    this.activeContextPanelTab = WorkbenchContextPanelTab.explorer,
    this.explorerMode = WorkspaceExplorerMode.hideIgnored,
    this.gitDiffViewMode = GitDiffViewMode.tree,
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
  final bool rightSidebarVisible;
  final double rightSidebarWidth;
  final WorkbenchContextPanelTab activeContextPanelTab;
  final WorkspaceExplorerMode explorerMode;
  final GitDiffViewMode gitDiffViewMode;

  static const WorkbenchViewPrefs defaults = WorkbenchViewPrefs(
    groupBy: WorkbenchGroupBy.project,
    projectSort: WorkbenchSortBy.name,
    workspaceSort: WorkbenchSortBy.name,
    selectedProjectIds: <String>{},
    collapsedProjectIds: <String>{},
    expandedWorkspaceIds: <String>{},
    rightSidebarVisible: true,
    rightSidebarWidth: 280,
    activeContextPanelTab: WorkbenchContextPanelTab.explorer,
    explorerMode: WorkspaceExplorerMode.hideIgnored,
    gitDiffViewMode: GitDiffViewMode.tree,
  );

  factory WorkbenchViewPrefs.fromJson(Map<String, Object?> json) =>
      WorkbenchViewPrefsMapper.fromMap(Map<String, dynamic>.from(json));
}
