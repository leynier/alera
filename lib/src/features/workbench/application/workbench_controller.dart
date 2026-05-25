// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/sembast_workbench_view_prefs_repository.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

class WorkbenchController extends StateNotifier<WorkbenchState> {
  WorkbenchController({
    required ProjectsService projectsService,
    required WorkbenchRepository repository,
    required WorkspaceService workspaceService,
    required WorkspaceTabService workspaceTabService,
    SembastWorkbenchViewPrefsRepository? viewPrefsRepository,
    Uuid? uuid,
  }) : _projectsService = projectsService,
       _repository = repository,
       _workspaceService = workspaceService,
       _workspaceTabService = workspaceTabService,
       _viewPrefsRepository = viewPrefsRepository,
       _uuid = uuid ?? const Uuid(),
       super(const WorkbenchState());

  final ProjectsService _projectsService;
  final WorkbenchRepository _repository;
  final WorkspaceService _workspaceService;
  final WorkspaceTabService _workspaceTabService;
  final SembastWorkbenchViewPrefsRepository? _viewPrefsRepository;
  final Uuid _uuid;

  StreamSubscription<List<Project>>? _projectsSub;
  final Map<String, StreamSubscription<List<Workspace>>> _workspaceSubs =
      <String, StreamSubscription<List<Workspace>>>{};
  final Map<String, StreamSubscription<List<WorkspaceTabRecord>>> _tabSubs =
      <String, StreamSubscription<List<WorkspaceTabRecord>>>{};
  // Tracks which project each workspace-tab subscription belongs to, so subs
  // can be pruned by project without relying on the (already-mutated) state.
  final Map<String, String> _tabSubProjectIds = <String, String>{};
  final Set<String> _ensuringMainWorkspaceProjectIds = <String>{};
  final Set<String> _loadingLayoutWorkspaceIds = <String>{};
  final Set<String> _closingTabWorkspaceIds = <String>{};

  bool _bootstrapStarted = false;

  Future<void> bootstrap() async {
    if (_bootstrapStarted) {
      return;
    }
    _bootstrapStarted = true;
    try {
      final repo = _viewPrefsRepository;
      if (repo != null) {
        try {
          final prefs = await repo.load();
          state = state.copyWith(viewPrefs: prefs);
        } catch (_) {
          // Fall back to defaults if loading fails; never block bootstrap.
        }
      }
      _projectsSub = _projectsService.projectRepository.watchAll().listen(
        _onProjectsChanged,
      );
      final initialProjects = await _projectsService.projectRepository
          .listAll();
      _onProjectsChanged(initialProjects);
      await Future.wait<void>(
        initialProjects.map(_ensureMainWorkspaceForProject),
      );
      state = state.copyWith(bootstrapped: true, clearError: true);
    } catch (error) {
      state = state.copyWith(
        bootstrapped: true,
        error: 'Failed to bootstrap workbench: $error',
      );
    }
  }

  Future<List<String>> listSourceBranches(Project project) {
    return _workspaceService.listSourceBranches(project);
  }

  Future<Project> addLocalProject({required String path, String? name}) async {
    try {
      final project = await _projectsService.addLocalProject(
        path: path,
        name: name,
      );
      await _activateAddedProject(project);
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<Project> cloneProject({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) async {
    try {
      final project = await _projectsService.cloneProject(
        gitUrl: gitUrl,
        destinationPath: destinationPath,
        name: name,
      );
      await _activateAddedProject(project);
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<Project> addProject({required String repoPath, String? name}) {
    return addLocalProject(path: repoPath, name: name);
  }

  Future<void> removeProject(String projectId) async {
    try {
      await _projectsService.removeProject(projectId);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<Workspace> createWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    String? name,
  }) async {
    try {
      final workspace = await _workspaceService.createLinkedWorkspace(
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        name: name,
      );
      await selectWorkspace(project: project, workspace: workspace);
      state = state.copyWith(clearError: true);
      return workspace;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> deleteWorkspace({
    required Project project,
    required Workspace workspace,
    bool deleteBranch = true,
  }) async {
    try {
      await _workspaceService.removeWorkspace(
        project: project,
        workspace: workspace,
        deleteBranch: deleteBranch,
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    // Selecting a workspace also reveals its sidebar terminal-tab list so the
    // user can jump into a tab right away. Subsequent toggles via the chevron
    // can hide it back independently of the active selection.
    final prefs = state.viewPrefs;
    final nextPrefs = prefs.expandedWorkspaceIds.contains(workspace.id)
        ? prefs
        : prefs.copyWith(
            expandedWorkspaceIds: <String>{
              ...prefs.expandedWorkspaceIds,
              workspace.id,
            },
          );
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      viewPrefs: nextPrefs,
      clearError: true,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
    await _workspaceTabService.ensureInitialTerminalTab(workspace.id);
    final tabs = await _workspaceTabService.listTabs(workspace.id);
    final layout = await _ensureWorkbenchLayout(workspace.id, tabs);
    await _applyLayout(layout, persist: false);
  }

  Future<void> activateProject(Project project) async {
    state = state.copyWith(
      activeProjectId: project.id,
      clearActiveWorkspaceId: true,
      clearError: true,
    );
  }

  Future<WorkspaceTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.createTerminalTab(workspace.id);
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      final nextLayout = layout.addTabToGroup(groupId: groupId, tabId: tab.id);
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
      state = state.copyWith(clearError: true);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> closeWorkspaceTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    try {
      _closingTabWorkspaceIds.add(workspace.id);
      await _workspaceTabService.closeTab(tabId);
      final remaining = state
          .tabsFor(workspace.id)
          .where((tab) => tab.id != tabId)
          .toList(growable: false);
      if (remaining.isNotEmpty) {
        _setTabsForWorkspace(workspace.id, remaining);
        final layout = _layoutForMutation(
          workspace.id,
          state.tabsFor(workspace.id),
        ).removeTab(tabId).sanitize(remaining);
        await _applyLayout(layout, persist: true);
      } else {
        _setTabsForWorkspace(workspace.id, const <WorkspaceTabRecord>[]);
        final layout = WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: const <String>[],
        );
        await _applyLayout(layout, persist: true);
      }
      state = state.copyWith(
        clearActiveWorkspaceId:
            remaining.isEmpty && state.activeWorkspaceId == workspace.id,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      _closingTabWorkspaceIds.remove(workspace.id);
    }
  }

  void setActiveTab({required String workspaceId, required String tabId}) {
    final layout = state.layoutFor(workspaceId);
    final groupId = layout?.groupIdForTab(tabId);
    _setActiveTabInternal(
      workspaceId: workspaceId,
      tabId: tabId,
      groupId: groupId,
    );
  }

  void setActiveWorkspaceTab({
    required String workspaceId,
    required String groupId,
    required String tabId,
  }) {
    _setActiveTabInternal(
      workspaceId: workspaceId,
      groupId: groupId,
      tabId: tabId,
    );
  }

  Future<void> moveWorkspaceTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  }) async {
    try {
      final tabs = state.tabsFor(workspaceId);
      final layout = _layoutForMutation(workspaceId, tabs);
      final nextLayout = layout
          .moveTab(
            tabId: tabId,
            targetGroupId: targetGroupId,
            zone: zone,
            newGroupId: _newPaneGroupId(),
            index: index,
          )
          .sanitize(tabs);
      await _applyLayout(nextLayout, persist: true);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.createTerminalTab(workspace.id);
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final nextLayout = layout
          .splitWithGroup(
            targetGroupId: groupId,
            zone: zone,
            newGroup: WorkbenchPaneGroup(
              id: _newPaneGroupId(),
              tabIds: <String>[tab.id],
              activeTabId: tab.id,
            ),
          )
          .sanitize(tabs);
      await _applyLayout(nextLayout, persist: true);
      state = state.copyWith(clearError: true);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> mergeWorkbenchGroupIntoSibling({
    required String workspaceId,
    required String groupId,
  }) async {
    try {
      final tabs = state.tabsFor(workspaceId);
      final layout = _layoutForMutation(
        workspaceId,
        tabs,
      ).mergeGroupIntoSibling(groupId).sanitize(tabs);
      await _applyLayout(layout, persist: true);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  void updateWorkbenchSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
  }) {
    final tabs = state.tabsFor(workspaceId);
    final layout = _layoutForMutation(
      workspaceId,
      tabs,
    ).updateSplitRatio(nodePath, ratio).sanitize(tabs);
    unawaited(_applyLayout(layout, persist: true));
  }

  void toggleExpanded(String projectId) {
    toggleProjectCollapsed(projectId);
  }

  void toggleProjectCollapsed(String projectId) {
    final next = Set<String>.from(state.viewPrefs.collapsedProjectIds);
    if (!next.add(projectId)) {
      next.remove(projectId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(collapsedProjectIds: next));
  }

  void setGroupBy(WorkbenchGroupBy groupBy) {
    if (state.viewPrefs.groupBy == groupBy) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(groupBy: groupBy));
  }

  void setProjectSort(WorkbenchSortBy sort) {
    if (state.viewPrefs.projectSort == sort) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(projectSort: sort));
  }

  void setWorkspaceSort(WorkbenchSortBy sort) {
    if (state.viewPrefs.workspaceSort == sort) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(workspaceSort: sort));
  }

  void toggleProjectFilter(String projectId) {
    final next = Set<String>.from(state.viewPrefs.selectedProjectIds);
    if (!next.add(projectId)) {
      next.remove(projectId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(selectedProjectIds: next));
  }

  void addProjectFilter(String projectId) {
    final current = state.viewPrefs.selectedProjectIds;
    if (current.contains(projectId)) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        selectedProjectIds: <String>{...current, projectId},
      ),
    );
  }

  void removeProjectFilter(String projectId) {
    final current = state.viewPrefs.selectedProjectIds;
    if (!current.contains(projectId)) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        selectedProjectIds: current.where((id) => id != projectId).toSet(),
      ),
    );
  }

  void clearProjectFilters() {
    if (state.viewPrefs.selectedProjectIds.isEmpty) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(selectedProjectIds: const <String>{}),
    );
  }

  /// Collapses or expands the appropriate items depending on the active group
  /// mode. In [WorkbenchGroupBy.project] this toggles every visible project
  /// group; in [WorkbenchGroupBy.none] it toggles the sidebar-visible
  /// terminal-tab list of the active workspace.
  void toggleCollapseAll() {
    final prefs = state.viewPrefs;
    if (prefs.groupBy == WorkbenchGroupBy.project) {
      final selected = prefs.selectedProjectIds;
      final visibleProjectIds = <String>[
        for (final project in state.projects)
          if (selected.isEmpty || selected.contains(project.id)) project.id,
      ];
      if (visibleProjectIds.isEmpty) {
        return;
      }
      final allCollapsed = visibleProjectIds.every(
        prefs.collapsedProjectIds.contains,
      );
      final next = Set<String>.from(prefs.collapsedProjectIds);
      if (allCollapsed) {
        next.removeAll(visibleProjectIds);
      } else {
        next.addAll(visibleProjectIds);
      }
      _updateViewPrefs(prefs.copyWith(collapsedProjectIds: next));
      return;
    }
    // Flat mode: toggle the expansion of every visible workspace.
    final allWorkspaceIds = <String>[
      for (final entry in state.workspacesByProject.entries)
        for (final workspace in entry.value) workspace.id,
    ];
    if (allWorkspaceIds.isEmpty) {
      return;
    }
    final anyExpanded = allWorkspaceIds.any(
      prefs.expandedWorkspaceIds.contains,
    );
    final next = Set<String>.from(prefs.expandedWorkspaceIds);
    if (anyExpanded) {
      next.removeAll(allWorkspaceIds);
    } else {
      next.addAll(allWorkspaceIds);
    }
    _updateViewPrefs(prefs.copyWith(expandedWorkspaceIds: next));
  }

  void toggleWorkspaceExpanded(String workspaceId) {
    final next = Set<String>.from(state.viewPrefs.expandedWorkspaceIds);
    if (!next.add(workspaceId)) {
      next.remove(workspaceId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(expandedWorkspaceIds: next));
  }

  void setWorkspaceExpanded(String workspaceId, bool expanded) {
    final current = state.viewPrefs.expandedWorkspaceIds;
    final isExpanded = current.contains(workspaceId);
    if (expanded == isExpanded) {
      return;
    }
    final next = Set<String>.from(current);
    if (expanded) {
      next.add(workspaceId);
    } else {
      next.remove(workspaceId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(expandedWorkspaceIds: next));
  }

  void _updateViewPrefs(WorkbenchViewPrefs prefs) {
    state = state.copyWith(viewPrefs: prefs);
    unawaited(_persistViewPrefs());
  }

  Future<void> _persistViewPrefs() async {
    final repo = _viewPrefsRepository;
    if (repo == null) {
      return;
    }
    try {
      await repo.save(state.viewPrefs);
    } catch (_) {
      // Persistence is best-effort; never surface an error from the UI path.
    }
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) {
      return;
    }
    state = state.copyWith(searchQuery: query);
  }

  void setCollapsed(bool value) {
    if (state.collapsed == value) {
      return;
    }
    state = state.copyWith(collapsed: value);
  }

  void setSidebarWidth(double value) {
    final clamped = value.clamp(
      AleraTokens.sidebarMinWidth,
      AleraTokens.sidebarMaxWidth,
    );
    if ((state.sidebarWidth - clamped).abs() < 0.5) {
      return;
    }
    state = state.copyWith(sidebarWidth: clamped);
  }

  void _onProjectsChanged(List<Project> projects) {
    final validProjectIds = <String>{
      for (final project in projects) project.id,
    };
    // Prune collapse/selection ids that point at removed projects. New
    // projects are not added to either set so they show up expanded and (when
    // there is no active selection) visible by default.
    final prefs = state.viewPrefs;
    final prunedCollapsed = prefs.collapsedProjectIds
        .where(validProjectIds.contains)
        .toSet();
    final prunedSelected = prefs.selectedProjectIds
        .where(validProjectIds.contains)
        .toSet();
    final prefsChanged =
        prunedCollapsed.length != prefs.collapsedProjectIds.length ||
        prunedSelected.length != prefs.selectedProjectIds.length;
    final nextViewPrefs = prefsChanged
        ? prefs.copyWith(
            collapsedProjectIds: prunedCollapsed,
            selectedProjectIds: prunedSelected,
          )
        : prefs;
    final updatedWorkspaces = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        if (validProjectIds.contains(entry.key)) entry.key: entry.value,
    };
    final liveWorkspaceIds = <String>{
      for (final workspaces in updatedWorkspaces.values)
        for (final workspace in workspaces) workspace.id,
    };
    final updatedTabs = <String, List<WorkspaceTabRecord>>{
      for (final entry in state.tabsByWorkspace.entries)
        if (liveWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final updatedLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (liveWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final updatedActiveTabs = <String, String>{
      for (final entry in state.activeTabIdByWorkspace.entries)
        if (liveWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };

    final currentActiveProjectId =
        state.activeProjectId != null &&
            validProjectIds.contains(state.activeProjectId)
        ? state.activeProjectId
        : (projects.isNotEmpty ? projects.first.id : null);
    final activeProjectId = currentActiveProjectId;
    final activeWorkspaceId = _resolveActiveWorkspaceId(
      activeProjectId: activeProjectId,
      workspacesByProject: updatedWorkspaces,
      preferredWorkspaceId: state.activeWorkspaceId,
    );

    state = state.copyWith(
      projects: projects,
      workspacesByProject: updatedWorkspaces,
      tabsByWorkspace: updatedTabs,
      viewPrefs: nextViewPrefs,
      activeProjectId: activeProjectId,
      clearActiveProjectId: activeProjectId == null,
      activeWorkspaceId: activeWorkspaceId,
      clearActiveWorkspaceId: activeWorkspaceId == null,
      activeTabIdByWorkspace: updatedActiveTabs,
      layoutByWorkspace: updatedLayouts,
    );
    if (prefsChanged) {
      unawaited(_persistViewPrefs());
    }

    for (final project in projects) {
      if (_workspaceSubs.containsKey(project.id)) {
        continue;
      }
      _workspaceSubs[project.id] = _repository
          .watchWorkspaces(project.id)
          .listen((workspaces) => _onWorkspacesChanged(project, workspaces));
      unawaited(_ensureMainWorkspaceForProject(project));
    }

    final removedProjectIds = _workspaceSubs.keys
        .where((projectId) => !validProjectIds.contains(projectId))
        .toList(growable: false);
    for (final projectId in removedProjectIds) {
      _workspaceSubs.remove(projectId)?.cancel();
      final removedWorkspaceIds = _tabSubProjectIds.entries
          .where((entry) => entry.value == projectId)
          .map((entry) => entry.key)
          .toList(growable: false);
      for (final workspaceId in removedWorkspaceIds) {
        _tabSubs.remove(workspaceId)?.cancel();
        _tabSubProjectIds.remove(workspaceId);
      }
    }
    _ensureSelectionHasTab();
  }

  void _onWorkspacesChanged(Project project, List<Workspace> workspaces) {
    final nextWorkspaces = Map<String, List<Workspace>>.from(
      state.workspacesByProject,
    )..[project.id] = workspaces;
    final liveWorkspaceIds = <String>{
      for (final workspace in workspaces) workspace.id,
    };
    final removedWorkspaceIds = _tabSubProjectIds.entries
        .where(
          (entry) =>
              entry.value == project.id &&
              !liveWorkspaceIds.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final workspaceId in removedWorkspaceIds) {
      _tabSubs.remove(workspaceId)?.cancel();
      _tabSubProjectIds.remove(workspaceId);
    }
    final nextLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    for (final workspace in workspaces) {
      if (_tabSubs.containsKey(workspace.id)) {
        continue;
      }
      _tabSubProjectIds[workspace.id] = project.id;
      unawaited(_loadLayoutForWorkspace(workspace.id));
      _tabSubs[workspace.id] = _repository
          .watchWorkspaceTabs(workspace.id)
          .listen((tabs) => _onTabsChanged(workspace.id, tabs));
    }
    // Preserve the active project while it is still valid; never silently jump
    // to a different project just because this project's workspaces changed.
    final candidateProjectId =
        (state.activeProjectId != null &&
            state.projects.any((proj) => proj.id == state.activeProjectId))
        ? state.activeProjectId
        : project.id;
    final activeWorkspaceId = _resolveActiveWorkspaceId(
      activeProjectId: candidateProjectId,
      workspacesByProject: nextWorkspaces,
      preferredWorkspaceId: state.activeWorkspaceId,
    );
    // Drop any expansion entries that pointed at workspaces that no longer
    // exist so the set stays tight.
    final viewPrefs = state.viewPrefs;
    final prunedExpanded = viewPrefs.expandedWorkspaceIds
        .where(
          (id) =>
              !removedWorkspaceIds.contains(id) ||
              liveWorkspaceIds.contains(id),
        )
        .toSet();
    final expansionChanged =
        prunedExpanded.length != viewPrefs.expandedWorkspaceIds.length;
    final nextViewPrefs = expansionChanged
        ? viewPrefs.copyWith(expandedWorkspaceIds: prunedExpanded)
        : viewPrefs;
    state = state.copyWith(
      workspacesByProject: nextWorkspaces,
      viewPrefs: nextViewPrefs,
      activeProjectId: candidateProjectId,
      clearActiveProjectId: candidateProjectId == null,
      activeWorkspaceId: activeWorkspaceId,
      clearActiveWorkspaceId: activeWorkspaceId == null,
      layoutByWorkspace: nextLayouts,
    );
    if (expansionChanged) {
      unawaited(_persistViewPrefs());
    }
    _ensureSelectionHasTab();
  }

  void _onTabsChanged(String workspaceId, List<WorkspaceTabRecord> tabs) {
    final nextTabs = Map<String, List<WorkspaceTabRecord>>.from(
      state.tabsByWorkspace,
    )..[workspaceId] = tabs;
    final currentLayout = state.layoutFor(workspaceId);
    if (currentLayout == null) {
      state = state.copyWith(tabsByWorkspace: nextTabs);
      if (!_loadingLayoutWorkspaceIds.contains(workspaceId)) {
        unawaited(_loadLayoutForWorkspace(workspaceId));
      }
      _ensureSelectionHasTab();
      return;
    }

    final layout = currentLayout.sanitize(tabs);
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[workspaceId] = layout;
    final activeTabs = _activeTabsWithLayout(layout);
    state = state.copyWith(
      tabsByWorkspace: nextTabs,
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: activeTabs,
    );
    unawaited(_repository.upsertWorkbenchLayout(layout));
    _ensureSelectionHasTab();
  }

  Future<void> _ensureMainWorkspaceForProject(Project project) async {
    if (!_ensuringMainWorkspaceProjectIds.add(project.id)) {
      return;
    }
    try {
      await _workspaceService.ensureMainWorkspace(project);
      await _workspaceService.reconcile(project);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          error: 'Failed to prepare workspace for "${project.name}": $error',
        );
      }
    } finally {
      _ensuringMainWorkspaceProjectIds.remove(project.id);
    }
  }

  Future<void> _activateAddedProject(Project project) async {
    await _ensureMainWorkspaceForProject(project);
    // Expand the project (remove from collapsed set if a stale id lingered).
    // Selection set is a positive filter — leave it untouched so we don't
    // accidentally start showing this brand-new project alone.
    final prefs = state.viewPrefs;
    final nextCollapsed = Set<String>.from(prefs.collapsedProjectIds)
      ..remove(project.id);
    final changedPrefs =
        nextCollapsed.length != prefs.collapsedProjectIds.length;
    final nextViewPrefs = changedPrefs
        ? prefs.copyWith(collapsedProjectIds: nextCollapsed)
        : prefs;
    state = state.copyWith(
      viewPrefs: nextViewPrefs,
      activeProjectId: project.id,
      clearActiveWorkspaceId: true,
      clearError: true,
    );
    if (changedPrefs) {
      unawaited(_persistViewPrefs());
    }
  }

  String? _resolveActiveWorkspaceId({
    required String? activeProjectId,
    required Map<String, List<Workspace>> workspacesByProject,
    required String? preferredWorkspaceId,
  }) {
    if (activeProjectId != null) {
      final workspaces =
          workspacesByProject[activeProjectId] ?? const <Workspace>[];
      // Keep an explicit selection only while it still belongs to the active
      // project. Missing or stale selections intentionally stay empty.
      if (preferredWorkspaceId != null &&
          workspaces.any((workspace) => workspace.id == preferredWorkspaceId)) {
        return preferredWorkspaceId;
      }
      return null;
    }
    // No active project: honor a still-valid explicit selection only.
    if (preferredWorkspaceId != null) {
      for (final workspaces in workspacesByProject.values) {
        if (workspaces.any(
          (workspace) => workspace.id == preferredWorkspaceId,
        )) {
          return preferredWorkspaceId;
        }
      }
    }
    return null;
  }

  void _ensureSelectionHasTab() {
    final workspace = state.activeWorkspace;
    if (workspace == null) {
      return;
    }
    if (_closingTabWorkspaceIds.contains(workspace.id)) {
      return;
    }
    if (state.tabsFor(workspace.id).isNotEmpty &&
        state.layoutFor(workspace.id) == null) {
      unawaited(_loadLayoutForWorkspace(workspace.id));
    }
  }

  Future<void> _loadLayoutForWorkspace(String workspaceId) async {
    if (!_loadingLayoutWorkspaceIds.add(workspaceId)) {
      return;
    }
    try {
      final tabs = await _workspaceTabService.listTabs(workspaceId);
      final layout = await _ensureWorkbenchLayout(workspaceId, tabs);
      await _applyLayout(layout, persist: true);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: error.toString());
      }
    } finally {
      _loadingLayoutWorkspaceIds.remove(workspaceId);
    }
  }

  Future<WorkbenchLayout> _ensureWorkbenchLayout(
    String workspaceId,
    List<WorkspaceTabRecord> tabs,
  ) async {
    final stored = await _repository.findWorkbenchLayout(workspaceId);
    final layout =
        stored ??
        WorkbenchLayout.single(
          workspaceId: workspaceId,
          tabIds: <String>[for (final tab in tabs) tab.id],
        );
    final sanitized = layout.sanitize(tabs);
    await _repository.upsertWorkbenchLayout(sanitized);
    return sanitized;
  }

  WorkbenchLayout _layoutForMutation(
    String workspaceId,
    List<WorkspaceTabRecord> tabs,
  ) {
    return (state.layoutFor(workspaceId) ??
            WorkbenchLayout.single(
              workspaceId: workspaceId,
              tabIds: <String>[for (final tab in tabs) tab.id],
            ))
        .sanitize(tabs);
  }

  Future<void> _applyLayout(
    WorkbenchLayout layout, {
    required bool persist,
  }) async {
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[layout.workspaceId] = layout;
    state = state.copyWith(
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: _activeTabsWithLayout(layout),
    );
    if (persist) {
      await _repository.upsertWorkbenchLayout(layout);
    }
  }

  Map<String, String> _activeTabsWithLayout(WorkbenchLayout layout) {
    final activeTabs = Map<String, String>.from(state.activeTabIdByWorkspace);
    final activeTabId = layout.activeTabId;
    if (activeTabId == null) {
      activeTabs.remove(layout.workspaceId);
    } else {
      activeTabs[layout.workspaceId] = activeTabId;
    }
    return activeTabs;
  }

  void _setTabsForWorkspace(String workspaceId, List<WorkspaceTabRecord> tabs) {
    final nextTabs = Map<String, List<WorkspaceTabRecord>>.from(
      state.tabsByWorkspace,
    )..[workspaceId] = tabs;
    state = state.copyWith(tabsByWorkspace: nextTabs);
  }

  String _newPaneGroupId() => 'pane-${_uuid.v4()}';

  void _setActiveTabInternal({
    required String workspaceId,
    required String tabId,
    String? groupId,
  }) {
    final layout = state.layoutFor(workspaceId);
    final resolvedGroupId = groupId ?? layout?.groupIdForTab(tabId);
    if (layout != null && resolvedGroupId != null) {
      final nextLayout = layout.setActiveTab(
        groupId: resolvedGroupId,
        tabId: tabId,
      );
      unawaited(_applyLayout(nextLayout, persist: true));
      return;
    }
    final next = Map<String, String>.from(state.activeTabIdByWorkspace)
      ..[workspaceId] = tabId;
    state = state.copyWith(activeTabIdByWorkspace: next);
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    for (final subscription in _workspaceSubs.values) {
      subscription.cancel();
    }
    for (final subscription in _tabSubs.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}
