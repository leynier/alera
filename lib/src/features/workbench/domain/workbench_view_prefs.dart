import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_view_prefs.mapper.dart';

@MappableEnum()
enum WorkbenchGroupBy { none, project, section }

@MappableEnum()
enum WorkbenchSortBy { name, recent, activity }

@MappableEnum()
enum WorkbenchContextPanelTab { explorer, search, gitDiff, pullRequests }

@MappableEnum()
enum WorkspaceExplorerMode { hideIgnored, showAll }

@MappableEnum()
enum GitDiffViewMode { tree, flat }

/// Whether Source Control lists files under Staged/Unstaged/Untracked headers
/// or in a single Changes section.
@MappableEnum()
enum GitDiffGroupMode { byArea, unified }

/// Preferred primary action for the Checks-panel create-PR split button.
@MappableEnum()
enum PullRequestCreateAction { publish, draft }

/// Sidebar visibility filter by workspace kind: the project's main worktree
/// ("Default Workspace" in the UI) versus linked worktrees.
@MappableEnum()
enum WorkspaceKindFilter { all, defaultOnly, nonDefaultOnly }

class WorkbenchViewPrefsDecodeHook extends MappingHook {
  const WorkbenchViewPrefsDecodeHook();

  @override
  Object? beforeDecode(Object? value) {
    if (value is! Map || value['activeContextPanelTab'] != 'agentCanvas') {
      return value;
    }
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
      'activeContextPanelTab': 'explorer',
    };
  }
}

@MappableClass(hook: WorkbenchViewPrefsDecodeHook())
class const WorkbenchViewPrefs({
  this.sectionSort = WorkbenchSortBy.name,
  this.collapsedSectionIds = const <String>{},
  this.othersSectionCollapsed = false,
  required this.groupBy,
  required this.projectSort,
  required this.workspaceSort,
  required this.selectedProjectIds,
  required this.collapsedProjectIds,
  required this.expandedWorkspaceIds,
  this.selectedTagIds = const <String>{},
  this.collapsedParentWorkspaceIds = const <String>{},
  this.pinnedSectionCollapsed = false,
  this.allSectionCollapsed = false,
  this.showPinnedWorkspacesBelow = true,
  this.sourceControlRootByWorkspaceId = const <String, String>{},
  this.rightSidebarVisible = true,
  this.rightSidebarWidth = 280,
  this.sidebarWidth = AleraTokens.sidebarDefaultWidth,
  this.activeContextPanelTab = WorkbenchContextPanelTab.explorer,
  this.explorerMode = WorkspaceExplorerMode.hideIgnored,
  this.gitDiffViewMode = GitDiffViewMode.tree,
  this.gitDiffGroupMode = GitDiffGroupMode.byArea,
  this.pullRequestCreateAction = PullRequestCreateAction.publish,
  this.workspaceKindFilter = WorkspaceKindFilter.all,
  this.showActiveWorkspacesOnly = false,
}) with WorkbenchViewPrefsMappable {
  final WorkbenchGroupBy groupBy;
  final WorkbenchSortBy sectionSort;
  final Set<String> collapsedSectionIds;
  final bool othersSectionCollapsed;
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

  /// Whether the pinned-workspaces sidebar section is currently collapsed.
  final bool pinnedSectionCollapsed;

  /// Whether the flat "All" sidebar section (group-by-none mode) is currently
  /// collapsed.
  final bool allSectionCollapsed;

  /// Whether pinned workspaces also appear in the regular project or "All"
  /// sections below the dedicated pinned section.
  final bool showPinnedWorkspacesBelow;

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

  /// Whether Source Control groups files by staged state or shows one list.
  final GitDiffGroupMode gitDiffGroupMode;

  /// Sticky create-PR split-button action (publish vs draft). App-wide and
  /// persisted with the rest of the workbench view prefs.
  final PullRequestCreateAction pullRequestCreateAction;

  /// Which workspace kinds the sidebar shows. Defaults to [WorkspaceKindFilter.all]
  /// so previously persisted prefs (missing the key) keep today's behavior.
  final WorkspaceKindFilter workspaceKindFilter;

  /// Whether the sidebar hides workspaces without an open terminal or Codex
  /// tab. Defaults to false so older persisted preferences keep showing all
  /// workspaces.
  final bool showActiveWorkspacesOnly;

  static const WorkbenchViewPrefs defaults = WorkbenchViewPrefs(
    groupBy: .project,
    projectSort: .name,
    workspaceSort: .name,
    selectedProjectIds: <String>{},
    collapsedProjectIds: <String>{},
    expandedWorkspaceIds: <String>{},
    selectedTagIds: <String>{},
    collapsedParentWorkspaceIds: <String>{},
    pinnedSectionCollapsed: false,
    allSectionCollapsed: false,
    showPinnedWorkspacesBelow: true,
    sourceControlRootByWorkspaceId: <String, String>{},
    rightSidebarVisible: true,
    rightSidebarWidth: 280,
    sidebarWidth: AleraTokens.sidebarDefaultWidth,
    activeContextPanelTab: .explorer,
    explorerMode: .hideIgnored,
    gitDiffViewMode: .tree,
    gitDiffGroupMode: .byArea,
    pullRequestCreateAction: .publish,
    workspaceKindFilter: .all,
    showActiveWorkspacesOnly: false,
  );

  factory fromJson(Map<String, Object?> json) =>
      WorkbenchViewPrefsMapper.fromMap(Map<String, dynamic>.from(json));
}
