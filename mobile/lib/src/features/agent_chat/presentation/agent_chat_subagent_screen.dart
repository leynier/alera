import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_bar.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_workflow_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A provider-native sub-agent on its own screen, read-only: what it was
/// asked, its own work, its result, and the sub-agent bar where the composer
/// would be. Work streams in from the chat; older work comes from
/// `agentChat.subagent`.
class const AgentChatSubagentScreen({
  super.key,
  required final AgentChatSubagentChat chat,
  required final String callId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = agentChatControllerProvider(
      chat.hostId,
      chat.workspaceId,
      chat.chatId,
    );
    final thread = ref.watch(controller.select((state) => state.value?.thread));
    final stored = ref.watch(
      agentChatSubagentTranscriptProvider(
        chat.hostId,
        chat.workspaceId,
        chat.chatId,
        callId,
      ),
    );
    final live = thread?.items ?? const <AgentChatItem>[];
    final transcript = stored.value;
    final call =
        live.where((item) => item.id == callId).firstOrNull ?? transcript?.call;
    if (call == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sub-agent')),
        body: stored.hasError
            ? AleraEmptyState(
                icon: AleraIcons.loadFailed,
                title: 'Could not open this sub-agent',
                message: agentChatErrorMessage(stored.error!),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final merged = <String, AgentChatItem>{
      for (final item in transcript?.items ?? const <AgentChatItem>[])
        item.id: item,
    };
    for (final item in agentChatSubagentDescendants(live, callId)) {
      merged[item.id] = item;
    }
    final timeline = AgentChatSubagentTimeline.build(
      call,
      merged.values.toList(),
    );
    final providerInstanceId = thread?.providerInstanceId ?? '';
    final instance = ref
        .watch(agentChatProvidersProvider(chat.hostId, chat.workspaceId))
        .value
        ?.where((candidate) => candidate.id == providerInstanceId)
        .firstOrNull;
    final model = call.subagentModel;
    final effort = call.subagentReasoningEffort;
    final stoppable =
        timeline.running &&
        (thread?.session.capabilities.stopSubagent ?? false);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(timeline.label, maxLines: 1, overflow: .ellipsis),
            Text(
              thread?.title.trim().isNotEmpty ?? false
                  ? thread!.title
                  : 'Sub-agent',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ],
        ),
        actions: <Widget>[
          if (stoppable)
            IconButton(
              key: const ValueKey<String>('agent-chat-subagent-stop'),
              tooltip: call.subagent?.workflow == null
                  ? 'Stop Sub-agent'
                  : 'Stop Workflow',
              icon: const Icon(
                AleraIcons.stopSubagent,
                color: AleraTokens.error,
              ),
              onPressed: () =>
                  unawaited(stopAgentChatSubagent(context, ref, chat, callId)),
            ),
        ],
      ),
      body: AgentChatScope(
        hostId: chat.hostId,
        workspaceId: chat.workspaceId,
        chatId: chat.chatId,
        cwd: thread?.session.cwd,
        child: ListView(
          key: ValueKey<String>('agent-chat-subagent-$callId'),
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            if (transcript?.truncated ?? false)
              _Notice(
                'Earlier work of this sub-agent is beyond what the runtime '
                'reads at once.',
              ),
            if (timeline.prompt case final prompt?)
              Container(
                margin: const EdgeInsets.only(bottom: AleraTokens.space12),
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.surface,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                ),
                child: SelectableText(prompt, style: theme.textTheme.bodySmall),
              ),
            if (call.workflowGroup case final workflow?)
              AgentChatWorkflowSection(
                chat: chat,
                callId: call.id,
                group: workflow,
              )
            else if (timeline.rows.isEmpty && timeline.running)
              _Notice('The sub-agent has not reported work yet.'),
            for (final row in timeline.rows) agentChatActivityRowView(row),
            if (timeline.summary case final summary?)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space12),
                child: AgentChatMarkdown(text: summary),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AgentChatSubagentBar(
        provider: thread?.provider ?? '',
        call: call,
        modelLabel:
            instance?.modelById(model)?.label ?? model ?? 'Provider Default',
        effortLabel: effort == null ? null : agentChatEffortLabel(effort),
        onOpenParent: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class const _Notice(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundFaint),
    ),
  );
}
