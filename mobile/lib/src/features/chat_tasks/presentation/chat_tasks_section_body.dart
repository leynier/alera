import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The runtime query behind a Chat Tasks group.
AgentChatTaskQuery mobileChatTaskQuery(AgentChatTaskBucket? bucket) =>
    AgentChatTaskQuery(
      attention: bucket == AgentChatTaskBucket.attention ? true : null,
      statuses: switch (bucket) {
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
      limit: 100,
    );

/// Chat Tasks in Activity: tasks handed to agent chats across projects and
/// hosts. It renders from the last list it read, so a reconnect keeps the
/// rows and their scroll offset; tapping a row opens the task, nothing else.
class const ChatTasksSectionBody({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(mobileChatTasksSupportedProvider(hostId));
    if (supported.value == false) {
      return const AleraEmptyState(
        icon: AleraIcons.systemUpdate,
        title: 'Update Required',
        message: 'Update Alera on this host to see and delegate chat tasks.',
      );
    }
    final bucket = ref.watch(mobileChatTaskFilterProvider(hostId));
    final provider = mobileChatTaskListProvider(
      hostId,
      mobileChatTaskQuery(bucket),
    );
    final read = ref.watch(provider);
    final page = read.value;
    final places = ref.watch(mobileChatTaskPlacesProvider(hostId)).value;
    final now = DateTime.now();
    final filter = _BucketFilter(
      selected: bucket,
      onSelected: ref
          .read(mobileChatTaskFilterProvider(hostId).notifier)
          .select,
    );
    if (page == null) {
      return Column(
        children: <Widget>[
          filter,
          Expanded(
            child: read.hasError
                ? AleraEmptyState(
                    title: 'Chat Tasks Unavailable',
                    message: agentChatOrchestrationErrorMessage(read.error!),
                    action: OutlinedButton(
                      onPressed: () => ref.invalidate(provider),
                      child: const Text('Retry'),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    final rows = <Widget>[
      for (final group in AgentChatTaskBucket.values)
        if (page.tasks.where((task) => AgentChatTaskBucket.of(task) == group)
            case final tasks when tasks.isNotEmpty) ...<Widget>[
          AleraSectionHeader(label: '${group.label} (${tasks.length})'),
          for (final task in tasks)
            ChatTaskTile(
              task: task,
              now: now,
              place: agentChatTaskPlaceLabel(
                task,
                projectName: places?.projectName(task.projectId),
                workspaceName: places?.workspace(task.workspaceId)?.name,
              ),
              onTap: () =>
                  unawaited(openChatTaskDetail(context, hostId, task.id)),
            ),
        ],
    ];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(provider),
      child: ListView(
        key: const PageStorageKey<String>('mobile-chat-tasks'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          filter,
          if (read.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.spaceLg,
              ),
              child: AleraNotice(
                message:
                    'This list may be out of date until the host reconnects.',
                icon: AleraIcons.cloudOff,
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: AleraTokens.contentPadding,
              child: Text(
                bucket == null
                    ? 'No chat tasks yet. Delegate a task to an agent chat in any project or host.'
                    : 'No chat tasks in this group.',
              ),
            ),
          ...rows,
          const SizedBox(height: AleraTokens.space48 + AleraTokens.spaceLg),
        ],
      ),
    );
  }
}

class const _BucketFilter({
  required final AgentChatTaskBucket? selected,
  required final ValueChanged<AgentChatTaskBucket?> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.spaceLg,
      vertical: AleraTokens.spaceSm,
    ),
    child: Wrap(
      spacing: AleraTokens.spaceSm,
      runSpacing: AleraTokens.spaceXs,
      children: <Widget>[
        ChoiceChip(
          key: const ValueKey<String>('chatTasksFilter:all'),
          label: const Text('All Tasks'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final bucket in AgentChatTaskBucket.values)
          ChoiceChip(
            key: ValueKey<String>('chatTasksFilter:${bucket.name}'),
            label: Text(bucket.label),
            selected: selected == bucket,
            onSelected: (_) => onSelected(bucket),
          ),
      ],
    ),
  );
}
