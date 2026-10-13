import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The master list of Chat Tasks: filters, then Attention, Active and
/// History groups. Presentational: rows, labels and callbacks come in.
class const ChatTaskList({
  super.key,
  required final List<AgentChatTask>? tasks,
  required final DateTime now,
  required final ValueChanged<String> onSelect,
  required final String Function(AgentChatTask task) placeOf,
  required final Widget filters,
  required final String emptyMessage,
  final String? selectedTaskId,
  final Widget? message,
  final Widget? footer,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = tasks ?? const <AgentChatTask>[];
    final entries = <Object>[
      for (final bucket in AgentChatTaskBucket.values)
        if (rows.any(
          (task) => AgentChatTaskBucket.of(task) == bucket,
        )) ...<Object>[
          bucket,
          ...rows.where((task) => AgentChatTaskBucket.of(task) == bucket),
        ],
    ];
    return ListView.builder(
      key: const PageStorageKey<String>('chat-tasks-list'),
      itemCount: entries.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) return filters;
        if (index == entries.length + 1) {
          return message ??
              (entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AleraTokens.space16),
                      child: Text(emptyMessage),
                    )
                  : const SizedBox.shrink());
        }
        if (index == entries.length + 2) {
          return footer ?? const SizedBox.shrink();
        }
        final entry = entries[index - 1];
        if (entry is AgentChatTaskBucket) {
          final count = rows
              .where((task) => AgentChatTaskBucket.of(task) == entry)
              .length;
          return AleraSectionHeader(
            label: '${entry.label} ($count)',
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space12,
              AleraTokens.space12,
              AleraTokens.space8,
              AleraTokens.space4,
            ),
          );
        }
        final task = entry as AgentChatTask;
        return ChatTaskRow(
          key: ValueKey<String>('chatTask:${task.id}'),
          task: task,
          now: now,
          place: placeOf(task),
          selected: task.id == selectedTaskId,
          onPressed: () => onSelect(task.id),
        );
      },
    );
  }
}

/// Title; status, why it needs attention and the agent; where it runs; age.
class const ChatTaskRow({
  super.key,
  required final AgentChatTask task,
  required final DateTime now,
  required final String place,
  required final bool selected,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraActivityRow(
    title: task.displayTitle,
    subtitle: chatTaskRowSubtitle(task),
    metadata: place,
    trailing: agentChatTaskAgeLabel(task.updatedAt, now),
    selected: selected,
    statusColor: chatTaskStatusTone(task.status).foreground,
    onPressed: onPressed,
  );
}

/// Group, project and workspace filters of the list.
class const ChatTaskFilters({
  super.key,
  required final AgentChatTaskBucket? bucket,
  required final List<AleraDropdownFieldEntry<String?>> projects,
  required final List<AleraDropdownFieldEntry<String?>> workspaces,
  required final String? projectId,
  required final String? workspaceId,
  required final bool filtered,
  required final ValueChanged<AgentChatTaskBucket?> onBucket,
  required final ValueChanged<String?> onProject,
  required final ValueChanged<String?> onWorkspace,
  required final VoidCallback onClear,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraDropdownField<AgentChatTaskBucket?>(
          key: const ValueKey<String>('chatTasksBucket'),
          value: bucket,
          labelText: 'Show',
          entries: <AleraDropdownFieldEntry<AgentChatTaskBucket?>>[
            const AleraDropdownFieldEntry<AgentChatTaskBucket?>(
              value: null,
              label: 'All Tasks',
            ),
            for (final value in AgentChatTaskBucket.values)
              AleraDropdownFieldEntry<AgentChatTaskBucket?>(
                value: value,
                label: value.label,
              ),
          ],
          onChanged: onBucket,
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraDropdownField<String?>(
          key: const ValueKey<String>('chatTasksProject'),
          value: projectId,
          labelText: 'Project',
          filterable: projects.length > 8,
          entries: projects,
          onChanged: onProject,
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraDropdownField<String?>(
          key: const ValueKey<String>('chatTasksWorkspace'),
          value: workspaceId,
          labelText: 'Workspace',
          filterable: workspaces.length > 8,
          entries: workspaces,
          onChanged: onWorkspace,
        ),
        if (filtered)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onClear,
              child: const Text('Clear Filters'),
            ),
          ),
      ],
    ),
  );
}
