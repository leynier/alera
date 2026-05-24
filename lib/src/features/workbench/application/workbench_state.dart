import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

class WorkbenchState {
  const WorkbenchState({
    this.projects = const <Project>[],
    this.workspacesByProject = const <String, List<Workspace>>{},
    this.tabsByWorkspace = const <String, List<TerminalTabRecord>>{},
    this.expandedProjectIds = const <String>{},
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
  final Map<String, List<TerminalTabRecord>> tabsByWorkspace;
  final Set<String> expandedProjectIds;
  final String? activeProjectId;
  final String? activeWorkspaceId;
  final Map<String, String> activeTabIdByWorkspace;
  final bool bootstrapped;
  final String? error;
  final String searchQuery;
  final bool collapsed;
  final double sidebarWidth;

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

  TerminalTabRecord? get activeTerminalTab {
    final workspace = activeWorkspace;
    if (workspace == null) {
      return null;
    }
    final tabId = activeTabIdByWorkspace[workspace.id];
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

  List<TerminalTabRecord> tabsFor(String workspaceId) {
    return tabsByWorkspace[workspaceId] ?? const <TerminalTabRecord>[];
  }

  bool hasSearchQuery() => searchQuery.trim().isNotEmpty;

  bool workspaceMatches(Workspace workspace) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return workspace.name.toLowerCase().contains(query) ||
        workspace.branch.toLowerCase().contains(query) ||
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

  WorkbenchState copyWith({
    List<Project>? projects,
    Map<String, List<Workspace>>? workspacesByProject,
    Map<String, List<TerminalTabRecord>>? tabsByWorkspace,
    Set<String>? expandedProjectIds,
    String? activeProjectId,
    bool clearActiveProjectId = false,
    String? activeWorkspaceId,
    bool clearActiveWorkspaceId = false,
    Map<String, String>? activeTabIdByWorkspace,
    bool? bootstrapped,
    String? error,
    bool clearError = false,
    String? searchQuery,
    bool? collapsed,
    double? sidebarWidth,
  }) {
    return WorkbenchState(
      projects: projects ?? this.projects,
      workspacesByProject: workspacesByProject ?? this.workspacesByProject,
      tabsByWorkspace: tabsByWorkspace ?? this.tabsByWorkspace,
      expandedProjectIds: expandedProjectIds ?? this.expandedProjectIds,
      activeProjectId: clearActiveProjectId
          ? null
          : (activeProjectId ?? this.activeProjectId),
      activeWorkspaceId: clearActiveWorkspaceId
          ? null
          : (activeWorkspaceId ?? this.activeWorkspaceId),
      activeTabIdByWorkspace:
          activeTabIdByWorkspace ?? this.activeTabIdByWorkspace,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      collapsed: collapsed ?? this.collapsed,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    );
  }
}
