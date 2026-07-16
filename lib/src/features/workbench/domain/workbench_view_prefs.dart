import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_view_prefs.mapper.dart';

@MappableEnum()
enum WorkbenchGroupBy { none, project }

@MappableEnum()
enum WorkbenchSortBy { name, recent, activity }

@MappableEnum()
enum WorkbenchContextPanelTab { explorer, search, gitDiff, pullRequests }

@MappableEnum()
enum WorkspaceExplorerMode { hideIgnored, showAll }

@MappableEnum()
enum GitDiffViewMode { tree, flat }

/// Preferred primary action for the Checks-panel create-PR split button.
@MappableEnum()
enum PullRequestCreateAction { publish, draft }

@MappableClass()
class WorkbenchViewPrefs with WorkbenchViewPrefsMappable {
  const WorkbenchViewPrefs({
    required this.groupBy,
    required this.projectSort,
    required this.workspaceSort,
    required this.selectedProjectIds,
    required this.collapsedProjectIds,
    required this.expandedWorkspaceIds,
    this.selectedTagIds = const <String>{},
    this.collapsedParentWorkspaceIds = const <String>{},
    this.sourceControlRootByWorkspaceId = const <String, String>{},
    this.rightSidebarVisible = true,
    this.rightSidebarWidth = 280,
    this.sidebarWidth = AleraTokens.sidebarDefaultWidth,
    this.activeContextPanelTab = WorkbenchContextPanelTab.explorer,
    this.explorerMode = WorkspaceExplorerMode.hideIgnored,
    this.gitDiffViewMode = GitDiffViewMode.tree,
    this.pullRequestCreateAction = PullRequestCreateAction.publish,
  });

  final WorkbenchGroupBy groupBy;
  final WorkbenchSortBy projectSort;
  final WorkbenchSortBy workspaceSort;

  /// Projects the user has explicitly added to the visibility filter. When the
  /// set is empty the sidebar shows every project; when non-empty it shows
  /// only the listed ones (positive selection, Orca-style).
  final Set<String> selectedProjectIds;
  final Set<String> collapsedProjectIds;

  /// Workspaces whose in-card sidebar agent section is currently expanded.
  /// Activating a workspace adds it to this set so agent runs are visible by
  /// default; the per-row chevron lets the user toggle membership without
  /// changing the active selection.
  final Set<String> expandedWorkspaceIds;

  /// Tags the user has explicitly added to the visibility filter. Empty means
  /// no tag filtering; non-empty shows workspaces carrying at least one of the
  /// selected tags (OR semantics, mirroring [selectedProjectIds]).
  final Set<String> selectedTagIds;

  /// Parent workspaces whose nested children are currently hidden in the
  /// sidebar tree.
  final Set<String> collapsedParentWorkspaceIds;

  /// Folder-workspace ids mapped to the workspace-relative Git folder that
  /// should back the Source Control tab.
  final Map<String, String> sourceControlRootByWorkspaceId;
  final bool rightSidebarVisible;
  final double rightSidebarWidth;

  /// Width of the left sidebar (project/workbench list panel). Persisted so
  /// the user's preferred panel size survives app restarts.
  final double sidebarWidth;

  final WorkbenchContextPanelTab activeContextPanelTab;
  final WorkspaceExplorerMode explorerMode;
  final GitDiffViewMode gitDiffViewMode;

  /// Sticky create-PR split-button action (publish vs draft). App-wide and
  /// persisted with the rest of the workbench view prefs.
  final PullRequestCreateAction pullRequestCreateAction;

  static const WorkbenchViewPrefs defaults = WorkbenchViewPrefs(
    groupBy: WorkbenchGroupBy.project,
    projectSort: WorkbenchSortBy.name,
    workspaceSort: WorkbenchSortBy.name,
    selectedProjectIds: <String>{},
    collapsedProjectIds: <String>{},
    expandedWorkspaceIds: <String>{},
    selectedTagIds: <String>{},
    collapsedParentWorkspaceIds: <String>{},
    sourceControlRootByWorkspaceId: <String, String>{},
    rightSidebarVisible: true,
    rightSidebarWidth: 280,
    sidebarWidth: AleraTokens.sidebarDefaultWidth,
    activeContextPanelTab: WorkbenchContextPanelTab.explorer,
    explorerMode: WorkspaceExplorerMode.hideIgnored,
    gitDiffViewMode: GitDiffViewMode.tree,
    pullRequestCreateAction: PullRequestCreateAction.publish,
  );

  factory WorkbenchViewPrefs.fromJson(Map<String, Object?> json) =>
      WorkbenchViewPrefsMapper.fromMap(Map<String, dynamic>.from(json));
}
