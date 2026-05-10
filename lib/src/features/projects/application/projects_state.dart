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
  });

  final List<Project> projects;
  final Map<String, List<ChatSummary>> chatsByProject;
  final Map<String, List<Worktree>> worktreesByProject;
  final Set<String> expandedProjectIds;
  final String? activeProjectId;
  final String? activeChatId;
  final bool bootstrapped;
  final String? error;

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
    );
  }
}
