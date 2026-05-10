import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/projects_controller.dart';
import 'package:alera/src/features/projects/application/projects_state.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/projects/presentation/delete_chat_dialog.dart';
import 'package:alera/src/features/projects/presentation/new_chat_dialog.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectSidebar extends ConsumerWidget {
  const ProjectSidebar({super.key, this.width = 264});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectsControllerProvider);
    final controller = ref.read(projectsControllerProvider.notifier);

    return SizedBox(
      width: width,
      child: Container(
        decoration: const BoxDecoration(
          color: AleraTokens.surfaceVariant,
          border: Border(right: BorderSide(color: AleraTokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SidebarHeader(onAddProject: () => _addProject(context, ref)),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: state.projects.isEmpty
                  ? _EmptyProjectsView(
                      onAddProject: () => _addProject(context, ref),
                    )
                  : _ProjectsList(
                      state: state,
                      controller: controller,
                      ref: ref,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addProject(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => const AddProjectDialog(),
    );
    if (result == null) {
      return;
    }
    try {
      await ref
          .read(projectsControllerProvider.notifier)
          .addProject(repoPath: result.repoPath, name: result.name);
      if (!context.mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project added',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!context.mounted) {
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

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.onAddProject});

  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space12,
        AleraTokens.space12,
        AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Projects',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 30),
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
              ),
            ),
          ),
        ],
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
          Icon(
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

class _ProjectsList extends StatelessWidget {
  const _ProjectsList({
    required this.state,
    required this.controller,
    required this.ref,
  });

  final ProjectsState state;
  final ProjectsController controller;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      itemCount: state.projects.length,
      itemBuilder: (context, index) {
        final project = state.projects[index];
        final expanded = state.expandedProjectIds.contains(project.id);
        final chats = state.chatsFor(project.id);
        final worktrees = state.worktreesFor(project.id);
        return _ProjectTile(
          project: project,
          expanded: expanded,
          chats: chats,
          worktrees: worktrees,
          activeChatId: state.activeChatId,
          onToggle: () => controller.toggleExpanded(project.id),
          onNewChat: () => _newChat(context, project, worktrees),
          onSelectChat: (chat) => _openChat(context, project, worktrees, chat),
          onDeleteChat: (chat) =>
              _deleteChat(context, project, worktrees, chat),
          onRemoveProject: () => _removeProject(context, project),
        );
      },
    );
  }

  Future<void> _newChat(
    BuildContext context,
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
    if (result == null) {
      return;
    }

    Worktree? worktree;
    if (result.useNewWorktree) {
      try {
        worktree = await controller.createWorktree(
          project: project,
          name: result.worktreeName!,
        );
      } catch (error) {
        if (!context.mounted) {
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
      title: result.title ?? 'new chat',
    );
  }

  Future<void> _openChat(
    BuildContext context,
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
    controller.setActiveSelection(projectId: project.id, chatId: chat.id);
    await session.activateChat(
      chat: chat,
      project: project,
      worktree: worktree,
    );
  }

  Future<void> _deleteChat(
    BuildContext context,
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
    if (action == null || action == DeleteChatAction.cancel) {
      return;
    }
    final removeWorktree = action == DeleteChatAction.deleteWorktree;
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
      if (!context.mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Chat removed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: error.toString(),
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> _removeProject(BuildContext context, Project project) async {
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
    if (confirmed != true) {
      return;
    }
    try {
      await controller.removeProject(project.id);
      if (!context.mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Project removed',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!context.mounted) {
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

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.expanded,
    required this.chats,
    required this.worktrees,
    required this.activeChatId,
    required this.onToggle,
    required this.onNewChat,
    required this.onSelectChat,
    required this.onDeleteChat,
    required this.onRemoveProject,
  });

  final Project project;
  final bool expanded;
  final List<ChatSummary> chats;
  final List<Worktree> worktrees;
  final String? activeChatId;
  final VoidCallback onToggle;
  final VoidCallback onNewChat;
  final ValueChanged<ChatSummary> onSelectChat;
  final ValueChanged<ChatSummary> onDeleteChat;
  final VoidCallback onRemoveProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worktreeById = <String, Worktree>{for (final w in worktrees) w.id: w};
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New chat',
                    onPressed: onNewChat,
                    icon: const Icon(Icons.add, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Project options',
                    icon: const Icon(Icons.more_horiz, size: 16),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'remove') {
                        onRemoveProject();
                      }
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Text('Remove project'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(
                left: AleraTokens.space20,
                right: AleraTokens.space4,
                bottom: AleraTokens.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (chats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AleraTokens.space8,
                        vertical: AleraTokens.space6,
                      ),
                      child: Text(
                        'No chats yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                    )
                  else
                    for (final chat in chats)
                      _ChatRow(
                        chat: chat,
                        worktree: chat.worktreeId == null
                            ? null
                            : worktreeById[chat.worktreeId],
                        isActive: chat.id == activeChatId,
                        onTap: () => onSelectChat(chat),
                        onDelete: () => onDeleteChat(chat),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.worktree,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  final ChatSummary chat;
  final Worktree? worktree;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          color: isActive ? AleraTokens.surfaceElevated : null,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.chat_bubble_outline,
              size: 14,
              color: isActive
                  ? AleraTokens.foreground
                  : AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    chat.title.isEmpty ? 'untitled chat' : chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isActive
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                  if (worktree != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AleraTokens.space6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AleraTokens.surface,
                          borderRadius: BorderRadius.circular(
                            AleraTokens.radiusSm,
                          ),
                          border: Border.all(color: AleraTokens.borderSubtle),
                        ),
                        child: Text(
                          'worktree: ${worktree!.name}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete chat',
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
