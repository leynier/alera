import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_location.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_detail_page.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_list.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_read_state.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The runtime query behind a Chat Tasks location.
AgentChatTaskQuery chatTaskQueryFor(ChatTasksLocation location) =>
    AgentChatTaskQuery(
      projectId: location.projectId,
      workspaceId: location.workspaceId,
      attention: location.bucket == AgentChatTaskBucket.attention ? true : null,
      statuses: switch (location.bucket) {
        AgentChatTaskBucket.active => <AgentChatTaskStatus>{
          for (final status in AgentChatTaskStatus.values)
            if (!status.settled) status,
        },
        AgentChatTaskBucket.history => <AgentChatTaskStatus>{
          for (final status in AgentChatTaskStatus.values)
            if (status.settled) status,
        },
        _ => const <AgentChatTaskStatus>{},
      },
      limit: location.limit,
    );

/// Reloads what Chat Tasks shows for [location].
void refreshChatTasks(WidgetRef ref, ChatTasksLocation location) {
  ref
    ..invalidate(chatTaskListProvider(chatTaskQueryFor(location)))
    ..invalidate(chatTaskAttentionProvider);
  final taskId = location.taskId;
  if (taskId == null) return;
  ref
    ..invalidate(chatTaskDetailProvider(taskId))
    ..invalidate(chatTaskRequestsProvider(taskId));
}

/// The Chat Tasks section of Activity: tasks handed to agent chats across
/// projects and hosts, beside the selected task. Selecting a task never
/// changes the active workspace.
class const ChatTasksSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(
      activityNavigationProvider.select((value) => value.chatTasks),
    );
    final navigation = ref.read(activityNavigationProvider.notifier);
    final provider = chatTaskListProvider(chatTaskQueryFor(location));
    final page = ref.watch(provider);
    final data = page.value;
    final workbench = ref.watch(workbenchControllerProvider);
    final now = ref.watch(agentChatClockProvider)();
    final allWorkspaces = workbench.workspacesByProject.values.expand(
      (items) => items,
    );
    final projectNames = <String, String>{
      for (final project in workbench.projects) project.id: project.name,
    };
    final workspaceNames = <String, String>{
      for (final workspace in allWorkspaces) workspace.id: workspace.name,
    };
    String placeOf(AgentChatTask task) => agentChatTaskPlaceLabel(
      task,
      projectName: projectNames[task.projectId],
      workspaceName: workspaceNames[task.workspaceId],
    );
    final filters = ChatTaskFilters(
      bucket: location.bucket,
      projectId: location.projectId,
      workspaceId: location.workspaceId,
      filtered: location.filtered,
      projects: <AleraDropdownFieldEntry<String?>>[
        const AleraDropdownFieldEntry<String?>(
          value: null,
          label: 'All Projects',
        ),
        for (final project in workbench.projects)
          AleraDropdownFieldEntry<String?>(
            value: project.id,
            label: project.name,
          ),
      ],
      workspaces: <AleraDropdownFieldEntry<String?>>[
        const AleraDropdownFieldEntry<String?>(
          value: null,
          label: 'All Workspaces',
        ),
        for (final workspace in allWorkspaces)
          if (location.projectId == null ||
              workspace.projectId == location.projectId)
            AleraDropdownFieldEntry<String?>(
              value: workspace.id,
              label: workspace.name,
            ),
      ],
      onBucket: navigation.filterChatTaskBucket,
      onProject: navigation.filterChatTaskProject,
      onWorkspace: navigation.filterChatTaskWorkspace,
      onClear: navigation.clearChatTaskFilters,
    );
    final stale = page.hasError && data != null;
    Widget master() => ChatTaskList(
      tasks: data?.tasks,
      now: now,
      selectedTaskId: location.taskId,
      onSelect: navigation.selectChatTask,
      placeOf: placeOf,
      filters: stale
          ? Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                filters,
                ChatTaskStaleNotice(onRefresh: () => ref.invalidate(provider)),
              ],
            )
          : filters,
      emptyMessage: location.filtered
          ? 'No chat tasks match these filters.'
          : 'No chat tasks yet.',
      message: data == null
          ? ChatTaskReadState(
              error: page.error,
              onRefresh: () => ref.invalidate(provider),
            )
          : null,
      footer: data?.nextCursor == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: OutlinedButton(
                onPressed: navigation.showMoreChatTasks,
                child: const Text('Load More Tasks'),
              ),
            ),
    );
    final taskId = location.taskId;
    final Widget detail = taskId != null
        ? ChatTaskDetailPage(key: ValueKey<String>(taskId), taskId: taskId)
        : _NoSelection(
            empty: data != null && data.tasks.isEmpty,
            filtered: location.filtered,
          );
    return FocusTraversalGroup(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (constraints.maxWidth <
              AleraTokens.wideContentBreakpoint * scale) {
            if (taskId == null) return master();
            return Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                TextButton.icon(
                  key: const ValueKey<String>('chatTasksBack'),
                  onPressed: () => navigation.selectChatTask(null),
                  icon: const Icon(AleraIcons.back, size: AleraTokens.iconMd),
                  label: const Text('Back To Chat Tasks'),
                ),
                Expanded(child: detail),
              ],
            );
          }
          return AleraMasterDetail(
            masterTitle: 'Chat Tasks',
            masterWidth: AleraTokens.sidebarDefaultWidth,
            masterMaxWidth: AleraTokens.masterDetailMaxWidth,
            master: master(),
            detail: detail,
          );
        },
      ),
    );
  }
}

class const _NoSelection({
  required final bool empty,
  required final bool filtered,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: AleraEmptyState(
          icon: AleraIcons.agent,
          title: empty
              ? filtered
                    ? 'No Matching Tasks'
                    : 'No Chat Tasks Yet'
              : 'Select a Task',
          message: empty
              ? filtered
                    ? 'Clear or adjust your filters to see other tasks.'
                    : 'Delegate a task to an agent chat in any project or host. Your active workspace stays unchanged.'
              : 'See where a task runs, what it returned and what it is waiting for. Selecting a task does not change your active workspace.',
          action: empty && !filtered
              ? FilledButton.icon(
                  key: const ValueKey<String>('chatTasksEmptyDelegate'),
                  onPressed:
                      ref.watch(chatTasksSupportedProvider).value ?? false
                      ? () => unawaited(showDelegateChatTaskDialog(context))
                      : null,
                  icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
                  label: const Text('Delegate Task'),
                )
              : null,
        ),
      ),
    ),
  );
}
