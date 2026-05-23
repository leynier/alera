import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/projects_controller.dart';
import 'package:alera/src/features/projects/application/projects_state.dart';
import 'package:alera/src/features/projects/application/sidebar_grouping.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/projects/presentation/delete_chat_dialog.dart';
import 'package:alera/src/features/projects/presentation/new_chat_dialog.dart';
import 'package:alera/src/features/projects/presentation/widgets/chat_row.dart';
import 'package:alera/src/features/projects/presentation/widgets/project_tile.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_collapsed_rail.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_resize_handle.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_search_bar.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_section_header.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectSidebar extends ConsumerStatefulWidget {
  const ProjectSidebar({super.key});

  @override
  ConsumerState<ProjectSidebar> createState() => _ProjectSidebarState();
}

class _ProjectSidebarState extends ConsumerState<ProjectSidebar> {
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _rootFocus = FocusNode(debugLabel: 'sidebar-root');

  @override
  void dispose() {
    _searchFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectsControllerProvider);
    final controller = ref.read(projectsControllerProvider.notifier);

    if (state.collapsed) {
      return _CollapsedSidebar(
        width: AleraTokens.sidebarCollapsedWidth,
        state: state,
        controller: controller,
        onAddProject: _addProject,
      );
    }

    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          const _FocusSearchIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          const _FocusSearchIntent(),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
          const _NewChatIntent(),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          const _NewChatIntent(),
    };
    final actions = <Type, Action<Intent>>{
      _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
        onInvoke: (_) {
          _searchFocus.requestFocus();
          return null;
        },
      ),
      _NewChatIntent: CallbackAction<_NewChatIntent>(
        onInvoke: (_) {
          if (state.projects.isNotEmpty) {
            _startNewChatForActiveProject(state);
          }
          return null;
        },
      ),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          focusNode: _rootFocus,
          canRequestFocus: false,
          skipTraversal: true,
          child: SizedBox(
            width: state.sidebarWidth,
            child: Stack(
              children: <Widget>[
                Container(
                  decoration: const BoxDecoration(
                    color: AleraTokens.surfaceVariant,
                    border: Border(
                      right: BorderSide(color: AleraTokens.borderSubtle),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SidebarBrandRow(
                        collapsed: false,
                        onToggleCollapsed: () =>
                            controller.setCollapsed(!state.collapsed),
                        onAddProject: _addProject,
                      ),
                      const Divider(height: 1, color: AleraTokens.borderSubtle),
                      SidebarSearchBar(
                        initialQuery: state.searchQuery,
                        focusNode: _searchFocus,
                        onChanged: controller.setSearchQuery,
                      ),
                      Expanded(
                        child: state.projects.isEmpty
                            ? _EmptyProjectsView(onAddProject: _addProject)
                            : _SidebarBody(
                                state: state,
                                controller: controller,
                                onSelectChat: _openChat,
                                onDeleteChat: _deleteChat,
                                onNewChatForProject: _newChatForProject,
                                onRemoveProject: _confirmRemoveProject,
                              ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: SidebarResizeHandle(
                    currentWidth: state.sidebarWidth,
                    onResize: controller.setSidebarWidth,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startNewChatForActiveProject(ProjectsState state) async {
    if (state.projects.isEmpty) {
      return;
    }
    final project = state.activeProject ?? state.projects.first;
    final worktrees = state.worktreesFor(project.id);
    await _newChatForProject(project, worktrees);
  }

  Future<void> _newChatForProject(
    Project project,
    List<Worktree> worktrees,
  ) async {
    final activeWorktrees = worktrees
        .where((w) => w.status == WorktreeStatus.active)
        .toList(growable: false);
    final result = await showDialog<NewChatResult>(
      context: context,
      builder: (_) => NewChatDialog(
        project: project,
        existingWorktreeNames: activeWorktrees.map((w) => w.name).toSet(),
      ),
    );
    if (result == null || !mounted) {
      return;
    }

    final controller = ref.read(projectsControllerProvider.notifier);
    Worktree? worktree;
    if (result.useNewWorktree) {
      try {
        worktree = await controller.createWorktree(
          project: project,
          name: result.worktreeName!,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: error.toString(),
          tone: AleraToastTone.error,
        );
        return;
      }
    }

    final session = ref.read(sessionControllerProvider.notifier);
    await session.activateChatStub(
      project: project,
      worktree: worktree,
      title: result.title ?? 'New chat',
    );
  }

  Future<void> _openChat(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  ) async {
    Worktree? worktree;
    if (chat.worktreeId != null) {
      for (final w in worktrees) {
        if (w.id == chat.worktreeId) {
          worktree = w;
          break;
        }
      }
    }
    final session = ref.read(sessionControllerProvider.notifier);
    ref
        .read(projectsControllerProvider.notifier)
        .setActiveSelection(projectId: project.id, chatId: chat.id);
    await session.activateChat(
      chat: chat,
      project: project,
      worktree: worktree,
    );
  }

  Future<void> _deleteChat(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  ) async {
    Worktree? worktree;
    if (chat.worktreeId != null) {
      for (final w in worktrees) {
        if (w.id == chat.worktreeId) {
          worktree = w;
          break;
        }
      }
    }
    final action = await showDialog<DeleteChatAction>(
      context: context,
      builder: (_) =>
          DeleteChatDialog(chatTitle: chat.title, worktree: worktree),
    );
    if (action == null || action == DeleteChatAction.cancel || !mounted) {
      return;
    }
    final removeWorktree = action == DeleteChatAction.deleteWorktree;
    final controller = ref.read(projectsControllerProvider.notifier);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .dropChatLocally(chat.id);
      await controller.deleteChat(
        chatId: chat.id,
        project: project,
        worktree: worktree,
        removeWorktree: removeWorktree,
      );
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Chat removed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _confirmRemoveProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove project?'),
        content: Text(
          'This unregisters "${project.name}" from Alera. Source files on disk are not deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AleraTokens.error,
              foregroundColor: AleraTokens.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final controller = ref.read(projectsControllerProvider.notifier);
    try {
      await controller.removeProject(project.id);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project removed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _addProject() async {
    final result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => const AddProjectDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(projectsControllerProvider.notifier)
          .addProject(repoPath: result.repoPath, name: result.name);
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project added',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }
}

class _CollapsedSidebar extends StatelessWidget {
  const _CollapsedSidebar({
    required this.width,
    required this.state,
    required this.controller,
    required this.onAddProject,
  });

  final double width;
  final ProjectsState state;
  final ProjectsController controller;
  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final chatCounts = <String, int>{
      for (final project in state.projects)
        project.id: state.chatsFor(project.id).length,
    };
    return SizedBox(
      width: width,
      child: Container(
        decoration: const BoxDecoration(
          color: AleraTokens.surfaceVariant,
          border: Border(right: BorderSide(color: AleraTokens.borderSubtle)),
        ),
        child: Column(
          children: <Widget>[
            SidebarBrandRow(
              collapsed: true,
              onToggleCollapsed: () =>
                  controller.setCollapsed(!state.collapsed),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: SidebarCollapsedRail(
                projects: state.projects,
                activeProjectId: state.activeProjectId,
                chatCountByProject: chatCounts,
                onSelectProject: (project) {
                  controller.setActiveSelection(projectId: project.id);
                  controller.setCollapsed(false);
                  if (!state.expandedProjectIds.contains(project.id)) {
                    controller.toggleExpanded(project.id);
                  }
                },
                onAddProject: () {
                  controller.setCollapsed(false);
                  onAddProject();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView({required this.onAddProject});

  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Icon(
            Icons.folder_outlined,
            color: AleraTokens.foregroundFaint,
            size: 36,
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            'No projects yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            'Add a git repository to start chatting.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
          const SizedBox(height: AleraTokens.space16),
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add your first project'),
          ),
        ],
      ),
    );
  }
}

class _SidebarBody extends StatelessWidget {
  const _SidebarBody({
    required this.state,
    required this.controller,
    required this.onSelectChat,
    required this.onDeleteChat,
    required this.onNewChatForProject,
    required this.onRemoveProject,
  });

  final ProjectsState state;
  final ProjectsController controller;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onSelectChat;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onDeleteChat;
  final Future<void> Function(Project project, List<Worktree> worktrees)
  onNewChatForProject;
  final Future<void> Function(Project project) onRemoveProject;

  @override
  Widget build(BuildContext context) {
    final searching = state.searchQuery.trim().isNotEmpty;
    if (searching) {
      return _SearchResults(
        state: state,
        controller: controller,
        onSelectChat: onSelectChat,
        onDeleteChat: onDeleteChat,
      );
    }
    return _ProjectsBrowser(
      state: state,
      controller: controller,
      onSelectChat: onSelectChat,
      onDeleteChat: onDeleteChat,
      onNewChatForProject: onNewChatForProject,
      onRemoveProject: onRemoveProject,
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.state,
    required this.controller,
    required this.onSelectChat,
    required this.onDeleteChat,
  });

  final ProjectsState state;
  final ProjectsController controller;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onSelectChat;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onDeleteChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = state.globalSearchResults();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Center(
          child: Text(
            'No chats match "${state.searchQuery}"',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
      );
    }
    final children = <Widget>[];
    for (final entry in results) {
      final project = entry.project;
      final worktrees = state.worktreesFor(project.id);
      final worktreeById = <String, Worktree>{
        for (final w in worktrees) w.id: w,
      };
      children.add(SidebarSectionHeader(label: project.name));
      for (final chat in entry.chats) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
            child: ChatRow(
              chat: chat,
              worktree: chat.worktreeId == null
                  ? null
                  : worktreeById[chat.worktreeId],
              isActive: chat.id == state.activeChatId,
              isPinned: state.pinnedChatIds.contains(chat.id),
              onTap: () => onSelectChat(project, worktrees, chat),
              onDelete: () => onDeleteChat(project, worktrees, chat),
              onTogglePin: () => controller.togglePinned(chat.id),
            ),
          ),
        );
      }
      children.add(const SizedBox(height: AleraTokens.space4));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      children: children,
    );
  }
}

class _ProjectsBrowser extends StatelessWidget {
  const _ProjectsBrowser({
    required this.state,
    required this.controller,
    required this.onSelectChat,
    required this.onDeleteChat,
    required this.onNewChatForProject,
    required this.onRemoveProject,
  });

  final ProjectsState state;
  final ProjectsController controller;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onSelectChat;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onDeleteChat;
  final Future<void> Function(Project project, List<Worktree> worktrees)
  onNewChatForProject;
  final Future<void> Function(Project project) onRemoveProject;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    final pinnedChats = state.pinnedChats();
    if (pinnedChats.isNotEmpty) {
      children.add(const SidebarSectionHeader(label: 'Pinned'));
      children.add(
        _PinnedSection(
          chats: pinnedChats,
          state: state,
          controller: controller,
          onSelectChat: onSelectChat,
          onDeleteChat: onDeleteChat,
        ),
      );
      children.add(const SizedBox(height: AleraTokens.space8));
    }

    for (final project in state.projects) {
      final expanded = state.expandedProjectIds.contains(project.id);
      final chats = state.chatsFor(project.id);
      final worktrees = state.worktreesFor(project.id);
      final worktreeById = <String, Worktree>{
        for (final w in worktrees) w.id: w,
      };
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space2,
          ),
          child: ProjectTile(
            project: project,
            expanded: expanded,
            chatCount: chats.length,
            onToggle: () => controller.toggleExpanded(project.id),
            onNewChat: () => onNewChatForProject(project, worktrees),
            onRemoveProject: () => onRemoveProject(project),
          ),
        ),
      );
      if (!expanded) {
        continue;
      }
      if (chats.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              left: AleraTokens.space24,
              right: AleraTokens.space8,
              top: AleraTokens.space2,
              bottom: AleraTokens.space4,
            ),
            child: _StartFirstChatRow(
              onTap: () => onNewChatForProject(project, worktrees),
            ),
          ),
        );
        continue;
      }

      final groups = groupChatsByRecency(chats, now: DateTime.now());
      for (final group in groups) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space16),
            child: SidebarSectionHeader(
              label: chatRecencyBucketLabel(group.bucket),
              padding: const EdgeInsets.only(
                left: AleraTokens.space12,
                right: AleraTokens.space8,
                top: AleraTokens.space2,
                bottom: AleraTokens.space2,
              ),
            ),
          ),
        );
        for (final chat in group.chats) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(
                left: AleraTokens.space20,
                right: AleraTokens.space8,
              ),
              child: ChatRow(
                chat: chat,
                worktree: chat.worktreeId == null
                    ? null
                    : worktreeById[chat.worktreeId],
                isActive: chat.id == state.activeChatId,
                isPinned: state.pinnedChatIds.contains(chat.id),
                onTap: () => onSelectChat(project, worktrees, chat),
                onDelete: () => onDeleteChat(project, worktrees, chat),
                onTogglePin: () => controller.togglePinned(chat.id),
              ),
            ),
          );
        }
      }
      children.add(const SizedBox(height: AleraTokens.space4));
    }

    return ListView(
      padding: const EdgeInsets.only(
        top: AleraTokens.space4,
        bottom: AleraTokens.space8,
      ),
      children: children,
    );
  }
}

class _StartFirstChatRow extends StatelessWidget {
  const _StartFirstChatRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.add, size: 14, color: AleraTokens.foregroundMuted),
            const SizedBox(width: AleraTokens.space8),
            Text(
              'Start the first chat',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedSection extends StatelessWidget {
  const _PinnedSection({
    required this.chats,
    required this.state,
    required this.controller,
    required this.onSelectChat,
    required this.onDeleteChat,
  });

  final List<ChatSummary> chats;
  final ProjectsState state;
  final ProjectsController controller;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onSelectChat;
  final Future<void> Function(
    Project project,
    List<Worktree> worktrees,
    ChatSummary chat,
  )
  onDeleteChat;

  Project? _projectFor(String projectId) {
    for (final p in state.projects) {
      if (p.id == projectId) {
        return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
      itemCount: chats.length,
      onReorderItem: (oldIndex, newIndex) {
        final legacyNewIndex = newIndex > oldIndex ? newIndex + 1 : newIndex;
        controller.reorderPinned(oldIndex, legacyNewIndex);
      },
      proxyDecorator: (child, _, _) {
        return Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.9, child: child),
        );
      },
      itemBuilder: (context, index) {
        final chat = chats[index];
        final project = _projectFor(chat.projectId);
        if (project == null) {
          return SizedBox.shrink(key: ValueKey('missing-${chat.id}'));
        }
        final worktrees = state.worktreesFor(project.id);
        final worktreeById = <String, Worktree>{
          for (final w in worktrees) w.id: w,
        };
        final worktree = chat.worktreeId == null
            ? null
            : worktreeById[chat.worktreeId];
        return Padding(
          key: ValueKey('pinned-${chat.id}'),
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AleraTokens.space2),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 12,
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ),
              Expanded(
                child: ChatRow(
                  chat: chat,
                  worktree: worktree,
                  isActive: chat.id == state.activeChatId,
                  isPinned: true,
                  onTap: () => onSelectChat(project, worktrees, chat),
                  onDelete: () => onDeleteChat(project, worktrees, chat),
                  onTogglePin: () => controller.togglePinned(chat.id),
                  leading: const Icon(
                    Icons.push_pin,
                    size: 11,
                    color: AleraTokens.foregroundMuted,
                  ),
                  dense: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _NewChatIntent extends Intent {
  const _NewChatIntent();
}
