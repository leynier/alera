import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat's lineage as a sheet, from the tab's actions: its parent and fork
/// source, forks, delegated chats and native sub-agents. Rows open what they
/// name only when pressed.
Future<void> showAgentChatLineageSheet(
  BuildContext context,
  AgentChatSubagentChat chat,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AgentChatLineageSheet(chat: chat),
);

class const AgentChatLineageSheet({
  super.key,
  required final AgentChatSubagentChat chat,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatLineageSheet> createState() =>
      _AgentChatLineageSheetState();
}

class _AgentChatLineageSheetState extends ConsumerState<AgentChatLineageSheet> {
  bool _previousExpanded = false;

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final controller = agentChatControllerProvider(
      chat.hostId,
      chat.workspaceId,
      chat.chatId,
    );
    final calls = ref.watch(
      controller.select(
        (state) => agentChatSubagentCalls(
          state.value?.thread.items ?? const <AgentChatItem>[],
        ),
      ),
    );
    final idle = ref.watch(
      controller.select(
        (state) => state.value?.thread.session.activeTurnId == null,
      ),
    );
    bool capability(String name) =>
        ref.watch(agentChatCapabilityProvider(chat.hostId, name)).value ??
        false;
    final threads = capability(AgentChatWire.subagentThreadsCapability);
    final mergeBack = capability(AgentChatWire.mergeBackCapability);
    final chats = ref.watch(agentChatRelatedChatsProvider(chat.hostId));
    final relationships = AgentChatRelationships.build(
      chatId: chat.chatId,
      chats: chats.value ?? const <AgentChatSummary>[],
      items: calls,
    );
    final theme = Theme.of(context);
    final previous = relationships.previous;
    Widget row(AgentChatRelation relation) => _RelationTile(
      relation: relation,
      chat: chat,
      chats: chats.value ?? const <AgentChatSummary>[],
      canOpenSubagent: threads,
      onMergeBack:
          mergeBack && idle && relation.kind == AgentChatRelationKind.forkSource
          ? () => unawaited(
              mergeBackAgentChat(context, ref, chat, relation.title),
            )
          : null,
    );
    return ListView(
      key: const ValueKey<String>('agent-chat-lineage-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space16,
            vertical: AleraTokens.space8,
          ),
          child: Text(
            relationships.heading,
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (relationships.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text(
              chats.isLoading
                  ? 'Loading related chats.'
                  : 'This chat has no parent, forks or sub-agents.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (final relation in relationships.related) row(relation),
        for (final relation in relationships.active) row(relation),
        if (previous.isNotEmpty)
          ListTile(
            key: const ValueKey<String>('agent-chat-lineage-previous'),
            leading: const Icon(AleraIcons.agent),
            title: const Text('Previous Agents'),
            trailing: Text(
              relationships.failedPreviousCount > 0
                  ? '${relationships.failedPreviousCount} failed · '
                        '${previous.length}'
                  : '${previous.length}',
            ),
            onTap: () => setState(() => _previousExpanded = !_previousExpanded),
          ),
        if (_previousExpanded)
          for (final relation in previous) row(relation),
      ],
    );
  }
}

class const _RelationTile({
  required final AgentChatRelation relation,
  required final AgentChatSubagentChat chat,
  required final List<AgentChatSummary> chats,
  required final bool canOpenSubagent,
  final VoidCallback? onMergeBack,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = relation.call;
    final icon = switch (relation.kind) {
      AgentChatRelationKind.parentChat ||
      AgentChatRelationKind.forkSource => AleraIcons.openParent,
      AgentChatRelationKind.fork => AleraIcons.gitFork,
      AgentChatRelationKind.delegatedChat || AgentChatRelationKind.subagent =>
        relation.workflow == null ? AleraIcons.agent : AleraIcons.workflow,
    };
    final relatedChatId = relation.chatId;
    final workspaceId = relatedChatId == null
        ? null
        : chats
              .where((summary) => summary.chatId == relatedChatId)
              .firstOrNull
              ?.workspaceId;
    VoidCallback? onTap;
    if (call != null && canOpenSubagent) {
      onTap = () {
        Navigator.of(context).pop();
        unawaited(openAgentChatSubagent(context, chat, call.id));
      };
    } else if (relatedChatId != null &&
        workspaceId != null &&
        !relation.missing) {
      onTap = () => unawaited(
        openMobileChatTaskChat(
          context,
          ref,
          hostId: chat.hostId,
          chatId: relatedChatId,
          workspaceId: workspaceId,
        ),
      );
    }
    final stoppable =
        call != null &&
        relation.active &&
        ref.watch(
          agentChatControllerProvider(
            chat.hostId,
            chat.workspaceId,
            chat.chatId,
          ).select(
            (state) =>
                state.value?.thread.session.capabilities.stopSubagent ?? false,
          ),
        ) &&
        canOpenSubagent;
    return ListTile(
      key: ValueKey<String>('agent-chat-lineage-${relation.key}'),
      leading: Icon(icon, color: relation.failed ? AleraTokens.error : null),
      title: Text(relation.title, maxLines: 1, overflow: .ellipsis),
      subtitle: Text('${relation.kindLabel} · ${relation.statusLabel}'),
      enabled: onTap != null || onMergeBack != null || stoppable,
      onTap: onTap,
      trailing: switch ((onMergeBack, stoppable)) {
        (final merge?, _) => IconButton(
          key: const ValueKey<String>('agent-chat-lineage-merge'),
          tooltip: 'Merge Back',
          icon: const Icon(AleraIcons.gitMerge),
          onPressed: merge,
        ),
        (null, true) => IconButton(
          key: ValueKey<String>('agent-chat-lineage-stop-${call!.id}'),
          tooltip: relation.workflow == null
              ? 'Stop Sub-agent'
              : 'Stop Workflow',
          icon: const Icon(AleraIcons.stopSubagent, color: AleraTokens.error),
          onPressed: () =>
              unawaited(stopAgentChatSubagent(context, ref, chat, call.id)),
        ),
        _ => null,
      },
    );
  }
}
