import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/application/projects_state.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/sidebar_prefs.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/features/projects/infra/sembast_sidebar_prefs_repository.dart';
import 'package:flutter_riverpod/legacy.dart';

class ProjectsController extends StateNotifier<ProjectsState> {
  ProjectsController({
    required ProjectsService projectsService,
    SembastSidebarPrefsRepository? sidebarPrefsRepository,
  }) : _service = projectsService,
       _sidebarPrefsRepository = sidebarPrefsRepository,
       super(const ProjectsState());

  final ProjectsService _service;
  final SembastSidebarPrefsRepository? _sidebarPrefsRepository;

  StreamSubscription<List<Project>>? _projectsSub;
  final Map<String, StreamSubscription<List<ChatSummary>>> _chatsSubs =
      <String, StreamSubscription<List<ChatSummary>>>{};
  final Map<String, StreamSubscription<List<Worktree>>> _worktreesSubs =
      <String, StreamSubscription<List<Worktree>>>{};

  bool _bootstrapStarted = false;
  Timer? _savePrefsTimer;
  static const Duration _savePrefsDebounce = Duration(milliseconds: 200);

  Future<void> bootstrap() async {
    if (_bootstrapStarted) {
      return;
    }
    _bootstrapStarted = true;
    try {
      if (_sidebarPrefsRepository != null) {
        try {
          final prefs = await _sidebarPrefsRepository!.load();
          state = state.copyWith(
            pinnedChatIds: prefs.pinnedChatIds,
            pinnedChatOrder: prefs.pinnedChatOrder,
            collapsed: prefs.collapsed,
            sidebarWidth: prefs.width,
          );
        } catch (_) {
          // Defaults already in state; ignore prefs load failure.
        }
      }
      _projectsSub = _service.projectRepository.watchAll().listen(
        _onProjectsChanged,
      );
      // Seed initial state synchronously so the sidebar can render before the
      // first stream tick lands.
      final initial = await _service.projectRepository.listAll();
      _onProjectsChanged(initial);
      state = state.copyWith(bootstrapped: true);
    } catch (error) {
      state = state.copyWith(
        bootstrapped: true,
        error: 'Failed to bootstrap projects: $error',
      );
    }
  }

  void _onProjectsChanged(List<Project> projects) {
    final byId = <String, Project>{for (final p in projects) p.id: p};
    final updatedExpanded = state.expandedProjectIds
        .where(byId.containsKey)
        .toSet();
    final updatedChats = <String, List<ChatSummary>>{
      for (final entry in state.chatsByProject.entries)
        if (byId.containsKey(entry.key)) entry.key: entry.value,
    };
    final updatedWorktrees = <String, List<Worktree>>{
      for (final entry in state.worktreesByProject.entries)
        if (byId.containsKey(entry.key)) entry.key: entry.value,
    };

    final activeProjectId =
        state.activeProjectId != null && byId.containsKey(state.activeProjectId)
        ? state.activeProjectId
        : null;

    state = state.copyWith(
      projects: projects,
      chatsByProject: updatedChats,
      worktreesByProject: updatedWorktrees,
      expandedProjectIds: updatedExpanded,
      activeProjectId: activeProjectId,
      clearActiveProjectId: activeProjectId == null,
    );

    // Subscribe to chats/worktrees streams for any new project.
    for (final project in projects) {
      if (!_chatsSubs.containsKey(project.id)) {
        _chatsSubs[project.id] = _service.chatRepository
            .watchByProject(project.id)
            .listen((chats) => _onChatsChanged(project.id, chats));
      }
      if (!_worktreesSubs.containsKey(project.id)) {
        _worktreesSubs[project.id] = _service.projectRepository
            .watchWorktrees(project.id)
            .listen((wts) => _onWorktreesChanged(project.id, wts));
      }
    }

    // Clean up subscriptions for projects that disappeared.
    final removed = _chatsSubs.keys
        .where((id) => !byId.containsKey(id))
        .toList(growable: false);
    for (final id in removed) {
      _chatsSubs.remove(id)?.cancel();
      _worktreesSubs.remove(id)?.cancel();
    }
  }

  void _onChatsChanged(String projectId, List<ChatSummary> chats) {
    final next = Map<String, List<ChatSummary>>.from(state.chatsByProject);
    next[projectId] = chats;
    final activeChatId = state.activeChatId;
    var pinnedChatIds = state.pinnedChatIds;
    var pinnedChatOrder = state.pinnedChatOrder;

    // Drop pinned ids whose chats no longer exist anywhere.
    if (pinnedChatIds.isNotEmpty) {
      final liveIds = <String>{
        for (final list in next.values)
          for (final chat in list) chat.id,
      };
      final filteredIds = pinnedChatIds.where(liveIds.contains).toSet();
      if (filteredIds.length != pinnedChatIds.length) {
        pinnedChatIds = filteredIds;
        pinnedChatOrder = <String>[
          for (final id in pinnedChatOrder)
            if (filteredIds.contains(id)) id,
        ];
        _persistSidebarPrefs();
      }
    }

    if (activeChatId != null) {
      final stillExists = chats.any((c) => c.id == activeChatId);
      if (!stillExists && state.activeProjectId == projectId) {
        state = state.copyWith(
          chatsByProject: next,
          clearActiveChatId: true,
          pinnedChatIds: pinnedChatIds,
          pinnedChatOrder: pinnedChatOrder,
        );
        return;
      }
    }
    state = state.copyWith(
      chatsByProject: next,
      pinnedChatIds: pinnedChatIds,
      pinnedChatOrder: pinnedChatOrder,
    );
  }

  void _onWorktreesChanged(String projectId, List<Worktree> wts) {
    final next = Map<String, List<Worktree>>.from(state.worktreesByProject);
    next[projectId] = wts;
    state = state.copyWith(worktreesByProject: next);
  }

  void toggleExpanded(String projectId) {
    final next = Set<String>.from(state.expandedProjectIds);
    if (!next.add(projectId)) {
      next.remove(projectId);
    }
    state = state.copyWith(expandedProjectIds: next);
  }

  void setActiveSelection({String? projectId, String? chatId}) {
    state = state.copyWith(
      activeProjectId: projectId,
      clearActiveProjectId: projectId == null,
      activeChatId: chatId,
      clearActiveChatId: chatId == null,
    );
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) {
      return;
    }
    state = state.copyWith(searchQuery: query);
  }

  void togglePinned(String chatId) {
    final ids = Set<String>.from(state.pinnedChatIds);
    final order = List<String>.from(state.pinnedChatOrder);
    if (ids.contains(chatId)) {
      ids.remove(chatId);
      order.remove(chatId);
    } else {
      ids.add(chatId);
      if (!order.contains(chatId)) {
        order.add(chatId);
      }
    }
    state = state.copyWith(pinnedChatIds: ids, pinnedChatOrder: order);
    _persistSidebarPrefs();
  }

  void reorderPinned(int oldIndex, int newIndex) {
    final order = List<String>.from(state.pinnedChatOrder);
    if (oldIndex < 0 || oldIndex >= order.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) {
      target -= 1;
    }
    if (target < 0) {
      target = 0;
    }
    if (target > order.length - 1) {
      target = order.length - 1;
    }
    final id = order.removeAt(oldIndex);
    order.insert(target, id);
    state = state.copyWith(pinnedChatOrder: order);
    _persistSidebarPrefs();
  }

  void setCollapsed(bool value) {
    if (state.collapsed == value) {
      return;
    }
    state = state.copyWith(collapsed: value);
    _persistSidebarPrefs();
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
    _persistSidebarPrefs();
  }

  void _persistSidebarPrefs() {
    final repo = _sidebarPrefsRepository;
    if (repo == null) {
      return;
    }
    _savePrefsTimer?.cancel();
    _savePrefsTimer = Timer(_savePrefsDebounce, () {
      final snapshot = SidebarPrefs(
        pinnedChatIds: state.pinnedChatIds,
        pinnedChatOrder: state.pinnedChatOrder,
        collapsed: state.collapsed,
        width: state.sidebarWidth,
      );
      // Fire and forget; failures should not crash the UI.
      repo.save(snapshot);
    });
  }

  Future<Project> addProject({required String repoPath, String? name}) async {
    try {
      final project = await _service.addProject(repoPath: repoPath, name: name);
      // Auto-expand the newly added project.
      final expanded = Set<String>.from(state.expandedProjectIds)
        ..add(project.id);
      state = state.copyWith(
        expandedProjectIds: expanded,
        activeProjectId: project.id,
        clearError: true,
      );
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> renameProject({
    required String projectId,
    required String name,
  }) async {
    try {
      await _service.renameProject(projectId: projectId, name: name);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> removeProject(String projectId) async {
    try {
      await _service.removeProject(projectId);
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<Worktree> createWorktree({
    required Project project,
    required String name,
  }) async {
    try {
      final worktree = await _service.createWorktree(
        project: project,
        name: name,
      );
      state = state.copyWith(clearError: true);
      return worktree;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> deleteChat({
    required String chatId,
    Project? project,
    Worktree? worktree,
    bool removeWorktree = false,
  }) async {
    try {
      await _service.deleteChat(
        chatId: chatId,
        project: project,
        worktree: worktree,
        removeWorktree: removeWorktree,
      );
      // Drop the chat from pinned state if it was pinned.
      var ids = state.pinnedChatIds;
      var order = state.pinnedChatOrder;
      if (ids.contains(chatId)) {
        ids = Set<String>.from(ids)..remove(chatId);
        order = List<String>.from(order)..remove(chatId);
      }
      state = state.copyWith(
        clearError: true,
        clearActiveChatId: state.activeChatId == chatId,
        pinnedChatIds: ids,
        pinnedChatOrder: order,
      );
      _persistSidebarPrefs();
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  @override
  void dispose() {
    _savePrefsTimer?.cancel();
    _projectsSub?.cancel();
    for (final sub in _chatsSubs.values) {
      sub.cancel();
    }
    for (final sub in _worktreesSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
