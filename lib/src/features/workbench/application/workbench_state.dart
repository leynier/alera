import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_state.mapper.dart';

@MappableClass()
class WorkbenchState with WorkbenchStateMappable {
  const WorkbenchState({
    this.projects = const <Project>[],
    this.workspacesByProject = const <String, List<Workspace>>{},
    this.tabsByWorkspace = const <String, List<WorkspaceTabRecord>>{},
    this.layoutByWorkspace = const <String, WorkbenchLayout>{},
    this.viewPrefs = WorkbenchViewPrefs.defaults,
    this.activeProjectId,
    this.activeWorkspaceId,
    this.activeTabIdByWorkspace = const <String, String>{},
    this.bootstrapped = false,
    this.error,
    this.searchQuery = '',
    this.collapsed = false,
    this.sidebarWidth = AleraTokens.sidebarDefaultWidth,
  });

  final List<Project> projects;
  final Map<String, List<Workspace>> workspacesByProject;
  final Map<String, List<WorkspaceTabRecord>> tabsByWorkspace;
  final Map<String, WorkbenchLayout> layoutByWorkspace;
  final WorkbenchViewPrefs viewPrefs;
  final String? activeProjectId;
  final String? activeWorkspaceId;
  final Map<String, String> activeTabIdByWorkspace;
  final bool bootstrapped;
  final String? error;
  final String searchQuery;
  final bool collapsed;
  final double sidebarWidth;

  /// Project ids that are visually expanded in the sidebar. Computed as the
  /// inverse of [WorkbenchViewPrefs.collapsedProjectIds] over the currently
  /// known projects so transient collapse state for removed projects is not
  /// surfaced to the UI.
  Set<String> get expandedProjectIds {
    final collapsed = viewPrefs.collapsedProjectIds;
    return <String>{
      for (final project in projects)
        if (!collapsed.contains(project.id)) project.id,
    };
  }

  Project? get activeProject {
    final projectId = activeProjectId;
    if (projectId == null) {
      return null;
    }
    for (final project in projects) {
      if (project.id == projectId) {
        return project;
      }
    }
    return null;
  }

  Workspace? get activeWorkspace {
    final workspaceId = activeWorkspaceId;
    if (workspaceId == null) {
      return null;
    }
    for (final workspaces in workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == workspaceId) {
          return workspace;
        }
      }
    }
    return null;
  }

  WorkspaceTabRecord? get activeWorkspaceTab {
    final workspace = activeWorkspace;
    if (workspace == null) {
      return null;
    }
    final tabId =
        layoutByWorkspace[workspace.id]?.activeTabId ??
        activeTabIdByWorkspace[workspace.id];
    if (tabId == null) {
      return null;
    }
    for (final tab in tabsFor(workspace.id)) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  List<Workspace> workspacesFor(String projectId) {
    return workspacesByProject[projectId] ?? const <Workspace>[];
  }

  List<WorkspaceTabRecord> tabsFor(String workspaceId) {
    return tabsByWorkspace[workspaceId] ?? const <WorkspaceTabRecord>[];
  }

  WorkbenchLayout? layoutFor(String workspaceId) {
    return layoutByWorkspace[workspaceId];
  }

  WorkbenchLayout? get activeLayout {
    final workspace = activeWorkspace;
    if (workspace == null) {
      return null;
    }
    return layoutByWorkspace[workspace.id];
  }

  List<WorkspaceTabRecord> tabsForGroup(String workspaceId, String groupId) {
    final layout = layoutFor(workspaceId);
    final group = layout?.groups[groupId];
    if (group == null) {
      return const <WorkspaceTabRecord>[];
    }
    final tabsById = <String, WorkspaceTabRecord>{
      for (final tab in tabsFor(workspaceId)) tab.id: tab,
    };
    return <WorkspaceTabRecord>[
      for (final tabId in group.tabIds)
        if (tabsById[tabId] case final WorkspaceTabRecord tab) tab,
    ];
  }

  bool hasSearchQuery() => searchQuery.trim().isNotEmpty;

  bool workspaceMatches(Workspace workspace) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return workspace.name.toLowerCase().contains(query) ||
        (workspace.branch?.toLowerCase().contains(query) ?? false) ||
        (workspace.sourceBranch?.toLowerCase().contains(query) ?? false);
  }

  List<({Project project, List<Workspace> workspaces})> searchResults() {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return const <({Project project, List<Workspace> workspaces})>[];
    }
    final results = <({Project project, List<Workspace> workspaces})>[];
    for (final project in projects) {
      final projectMatches = project.name.toLowerCase().contains(query);
      final matches = <Workspace>[
        for (final workspace in workspacesFor(project.id))
          if (projectMatches || workspaceMatches(workspace)) workspace,
      ];
      if (matches.isNotEmpty) {
        results.add((project: project, workspaces: matches));
      }
    }
    return results;
  }
}
