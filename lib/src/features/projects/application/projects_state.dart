import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';

class ProjectsState {
  const ProjectsState({
    this.projects = const <Project>[],
    this.chatsByProject = const <String, List<ChatSummary>>{},
    this.worktreesByProject = const <String, List<Worktree>>{},
    this.expandedProjectIds = const <String>{},
    this.activeProjectId,
    this.activeChatId,
    this.bootstrapped = false,
    this.error,
    this.searchQuery = '',
    this.pinnedChatIds = const <String>{},
    this.pinnedChatOrder = const <String>[],
    this.collapsed = false,
    this.sidebarWidth = AleraTokens.sidebarDefaultWidth,
  });

  final List<Project> projects;
  final Map<String, List<ChatSummary>> chatsByProject;
  final Map<String, List<Worktree>> worktreesByProject;
  final Set<String> expandedProjectIds;
  final String? activeProjectId;
  final String? activeChatId;
  final bool bootstrapped;
  final String? error;
  final String searchQuery;
  final Set<String> pinnedChatIds;
  final List<String> pinnedChatOrder;
  final bool collapsed;
  final double sidebarWidth;

  Project? get activeProject {
    if (activeProjectId == null) {
      return null;
    }
    for (final project in projects) {
      if (project.id == activeProjectId) {
        return project;
      }
    }
    return null;
  }

  List<ChatSummary> chatsFor(String projectId) {
    return chatsByProject[projectId] ?? const <ChatSummary>[];
  }

  List<Worktree> worktreesFor(String projectId) {
    return worktreesByProject[projectId] ?? const <Worktree>[];
  }

  /// Chats fijados, en el orden persistido. Ignora ids que ya no existen en la
  /// lista global de chats. Cuando hay ids en `pinnedChatIds` que no aparecen
  /// en `pinnedChatOrder`, se anexan al final preservando el orden de inserción
  /// del Set para mantener determinismo.
  List<ChatSummary> pinnedChats() {
    if (pinnedChatIds.isEmpty) {
      return const <ChatSummary>[];
    }
    final byId = <String, ChatSummary>{};
    for (final entry in chatsByProject.values) {
      for (final chat in entry) {
        byId[chat.id] = chat;
      }
    }
    final ordered = <ChatSummary>[];
    final seen = <String>{};
    for (final id in pinnedChatOrder) {
      if (!pinnedChatIds.contains(id) || seen.contains(id)) {
        continue;
      }
      final chat = byId[id];
      if (chat != null) {
        ordered.add(chat);
        seen.add(id);
      }
    }
    for (final id in pinnedChatIds) {
      if (seen.contains(id)) {
        continue;
      }
      final chat = byId[id];
      if (chat != null) {
        ordered.add(chat);
      }
    }
    return ordered;
  }

  /// Chats de un proyecto filtrados por la búsqueda actual. Aplica match
  /// case-insensitive contra el título; cuando `searchQuery` está vacío,
  /// devuelve la lista intacta.
  List<ChatSummary> filteredChatsFor(String projectId) {
    final all = chatsFor(projectId);
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return all;
    }
    return <ChatSummary>[
      for (final chat in all)
        if (chat.title.toLowerCase().contains(query)) chat,
    ];
  }

  /// Resultados globales de búsqueda agrupados por proyecto. Solo es relevante
  /// cuando `searchQuery` no está vacío.
  List<({Project project, List<ChatSummary> chats})> globalSearchResults() {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return const <({Project project, List<ChatSummary> chats})>[];
    }
    final results = <({Project project, List<ChatSummary> chats})>[];
    for (final project in projects) {
      final matches = <ChatSummary>[
        for (final chat in chatsFor(project.id))
          if (chat.title.toLowerCase().contains(query)) chat,
      ];
      if (matches.isNotEmpty) {
        results.add((project: project, chats: matches));
      }
    }
    return results;
  }

  ProjectsState copyWith({
    List<Project>? projects,
    Map<String, List<ChatSummary>>? chatsByProject,
    Map<String, List<Worktree>>? worktreesByProject,
    Set<String>? expandedProjectIds,
    String? activeProjectId,
    bool clearActiveProjectId = false,
    String? activeChatId,
    bool clearActiveChatId = false,
    bool? bootstrapped,
    String? error,
    bool clearError = false,
    String? searchQuery,
    Set<String>? pinnedChatIds,
    List<String>? pinnedChatOrder,
    bool? collapsed,
    double? sidebarWidth,
  }) {
    return ProjectsState(
      projects: projects ?? this.projects,
      chatsByProject: chatsByProject ?? this.chatsByProject,
      worktreesByProject: worktreesByProject ?? this.worktreesByProject,
      expandedProjectIds: expandedProjectIds ?? this.expandedProjectIds,
      activeProjectId: clearActiveProjectId
          ? null
          : (activeProjectId ?? this.activeProjectId),
      activeChatId: clearActiveChatId
          ? null
          : (activeChatId ?? this.activeChatId),
      bootstrapped: bootstrapped ?? this.bootstrapped,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      pinnedChatIds: pinnedChatIds ?? this.pinnedChatIds,
      pinnedChatOrder: pinnedChatOrder ?? this.pinnedChatOrder,
      collapsed: collapsed ?? this.collapsed,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    );
  }
}
