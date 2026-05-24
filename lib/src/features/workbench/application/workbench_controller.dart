// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/terminal_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

class WorkbenchController extends StateNotifier<WorkbenchState> {
  WorkbenchController({
    required ProjectsService projectsService,
    required WorkbenchRepository repository,
    required WorkspaceService workspaceService,
    required TerminalTabService terminalTabService,
    Uuid? uuid,
  }) : _projectsService = projectsService,
       _repository = repository,
       _workspaceService = workspaceService,
       _terminalTabService = terminalTabService,
       _uuid = uuid ?? const Uuid(),
       super(const WorkbenchState());

  final ProjectsService _projectsService;
  final WorkbenchRepository _repository;
  final WorkspaceService _workspaceService;
  final TerminalTabService _terminalTabService;
  final Uuid _uuid;

  StreamSubscription<List<Project>>? _projectsSub;
  final Map<String, StreamSubscription<List<Workspace>>> _workspaceSubs =
      <String, StreamSubscription<List<Workspace>>>{};
  final Map<String, StreamSubscription<List<TerminalTabRecord>>> _tabSubs =
      <String, StreamSubscription<List<TerminalTabRecord>>>{};
  // Tracks which project each terminal-tab subscription belongs to, so subs can
  // be pruned by project without relying on the (already-mutated) state.
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

  Future<Project> addProject({required String repoPath, String? name}) async {
    try {
      final project = await _projectsService.addProject(
        repoPath: repoPath,
        name: name,
      );
      await _ensureMainWorkspaceForProject(project);
      state = state.copyWith(
        expandedProjectIds: Set<String>.from(state.expandedProjectIds)
          ..add(project.id),
        activeProjectId: project.id,
        clearError: true,
      );
      final workspace = await _firstSelectableWorkspace(project.id);
      if (workspace != null) {
        await selectWorkspace(project: project, workspace: workspace);
      }
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
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
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      clearError: true,
    );
    await _terminalTabService.ensureInitialTab(workspace.id);
    final tabs = await _terminalTabService.listTabs(workspace.id);
    final layout = await _ensureWorkbenchLayout(workspace.id, tabs);
    await _applyLayout(layout, persist: false);
  }

  Future<void> activateProject(Project project) async {
    state = state.copyWith(activeProjectId: project.id, clearError: true);
    final workspace = await _firstSelectableWorkspace(project.id);
    if (workspace == null) {
      state = state.copyWith(clearActiveWorkspaceId: true);
      return;
    }
    await selectWorkspace(project: project, workspace: workspace);
  }

  Future<TerminalTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _terminalTabService.createTab(workspace.id);
      final tabs = <TerminalTabRecord>[...previousTabs, tab];
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

  Future<void> closeTerminalTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    try {
      _closingTabWorkspaceIds.add(workspace.id);
      await _terminalTabService.closeTab(tabId);
      final remaining = state
          .tabsFor(workspace.id)
          .where((tab) => tab.id != tabId)
          .toList(growable: false);
      if (remaining.isEmpty && state.activeWorkspaceId == workspace.id) {
        final replacement = await _terminalTabService.createTab(workspace.id);
        _setTabsForWorkspace(workspace.id, <TerminalTabRecord>[replacement]);
        final nextLayout = WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[replacement.id],
        );
        await _applyLayout(nextLayout, persist: true);
      } else if (remaining.isNotEmpty) {
        _setTabsForWorkspace(workspace.id, remaining);
        final layout = _layoutForMutation(
          workspace.id,
          state.tabsFor(workspace.id),
        ).removeTab(tabId).sanitize(remaining);
        await _applyLayout(layout, persist: true);
      } else {
        _setTabsForWorkspace(workspace.id, const <TerminalTabRecord>[]);
        final layout = WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: const <String>[],
        );
        await _applyLayout(layout, persist: true);
      }
      state = state.copyWith(clearError: true);
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

  void setActiveWorkbenchTab({
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

  Future<void> moveWorkbenchTab({
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

  Future<TerminalTabRecord> splitWorkbenchGroup({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _terminalTabService.createTab(workspace.id);
      final tabs = <TerminalTabRecord>[...previousTabs, tab];
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
    final next = Set<String>.from(state.expandedProjectIds);
    if (!next.add(projectId)) {
      next.remove(projectId);
    }
    state = state.copyWith(expandedProjectIds: next);
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
    final knownProjectIds = <String>{
      for (final project in state.projects) project.id,
    };
    // Auto-expand only newly added projects; preserve the user's collapse state
    // for projects we already knew about.
    final newProjectIds = validProjectIds.where(
      (projectId) => !knownProjectIds.contains(projectId),
    );
    final updatedExpanded =
        state.expandedProjectIds.where(validProjectIds.contains).toSet()
          ..addAll(newProjectIds);
    final updatedWorkspaces = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        if (validProjectIds.contains(entry.key)) entry.key: entry.value,
    };
    final liveWorkspaceIds = <String>{
      for (final workspaces in updatedWorkspaces.values)
        for (final workspace in workspaces) workspace.id,
    };
    final updatedTabs = <String, List<TerminalTabRecord>>{
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
      expandedProjectIds: updatedExpanded,
      activeProjectId: activeProjectId,
      clearActiveProjectId: activeProjectId == null,
      activeWorkspaceId: activeWorkspaceId,
      clearActiveWorkspaceId: activeWorkspaceId == null,
      activeTabIdByWorkspace: updatedActiveTabs,
      layoutByWorkspace: updatedLayouts,
    );

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
          .watchWorkbenchTabs(workspace.id)
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
    state = state.copyWith(
      workspacesByProject: nextWorkspaces,
      activeProjectId: candidateProjectId,
      clearActiveProjectId: candidateProjectId == null,
      activeWorkspaceId: activeWorkspaceId,
      clearActiveWorkspaceId: activeWorkspaceId == null,
      layoutByWorkspace: nextLayouts,
    );
    _ensureSelectionHasTab();
  }

  void _onTabsChanged(String workspaceId, List<TerminalTabRecord> tabs) {
    final nextTabs = Map<String, List<TerminalTabRecord>>.from(
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

  Future<Workspace?> _firstSelectableWorkspace(String projectId) async {
    final current = state.workspacesFor(projectId);
    if (current.isNotEmpty) {
      return current.first;
    }
    final fresh = await _repository.listWorkspaces(projectId);
    if (fresh.isEmpty) {
      return null;
    }
    return fresh.first;
  }

  String? _resolveActiveWorkspaceId({
    required String? activeProjectId,
    required Map<String, List<Workspace>> workspacesByProject,
    required String? preferredWorkspaceId,
  }) {
    if (activeProjectId != null) {
      final workspaces =
          workspacesByProject[activeProjectId] ?? const <Workspace>[];
      // Keep the current selection only when it still belongs to the active
      // project; otherwise fall back to that project's first workspace. Never
      // resolve to a workspace from a different project.
      if (preferredWorkspaceId != null &&
          workspaces.any((workspace) => workspace.id == preferredWorkspaceId)) {
        return preferredWorkspaceId;
      }
      return workspaces.isEmpty ? null : workspaces.first.id;
    }
    // No active project: honor a still-valid selection, else pick the first
    // workspace anywhere.
    if (preferredWorkspaceId != null) {
      for (final workspaces in workspacesByProject.values) {
        if (workspaces.any(
          (workspace) => workspace.id == preferredWorkspaceId,
        )) {
          return preferredWorkspaceId;
        }
      }
    }
    for (final workspaces in workspacesByProject.values) {
      if (workspaces.isNotEmpty) {
        return workspaces.first.id;
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
    if (state.tabsFor(workspace.id).isEmpty) {
      unawaited(_terminalTabService.ensureInitialTab(workspace.id));
      return;
    }
    if (state.layoutFor(workspace.id) == null) {
      unawaited(_loadLayoutForWorkspace(workspace.id));
    }
  }

  Future<void> _loadLayoutForWorkspace(String workspaceId) async {
    if (!_loadingLayoutWorkspaceIds.add(workspaceId)) {
      return;
    }
    try {
      final tabs = await _terminalTabService.listTabs(workspaceId);
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
    List<TerminalTabRecord> tabs,
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
    List<TerminalTabRecord> tabs,
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

  void _setTabsForWorkspace(String workspaceId, List<TerminalTabRecord> tabs) {
    final nextTabs = Map<String, List<TerminalTabRecord>>.from(
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
