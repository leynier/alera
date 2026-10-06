import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/agent_conversation_models.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every message of one agent conversation, in order. Read only: opening it
/// never marks anything read for the agents.
class const AgentConversationScreen({
  super.key,
  required final String hostId,
  required final AgentConversation conversation,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mobileAgentConversationDetailProvider(
      hostId,
      conversation.threadId,
    );
    final detail = ref.watch(provider);
    final labels =
        ref.watch(mobileInboxHandleLabelsProvider(hostId)).value ??
        const <String, String>{};
    return Scaffold(
      appBar: AppBar(
        title: Text(
          conversation.subject.isEmpty ? 'Conversation' : conversation.subject,
          maxLines: 1,
          overflow: .ellipsis,
        ),
      ),
      body: SafeArea(
        child: switch (detail) {
          AsyncValue(value: null, hasError: true, :final error) =>
            AleraEmptyState(
              icon: AleraIcons.comment,
              title: 'Conversation Unavailable',
              message: 'The host could not load this conversation.',
              detail: '$error',
              action: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Retry'),
              ),
            ),
          AsyncValue(value: null) => const Center(
            child: CircularProgressIndicator(),
          ),
          AsyncValue(value: final value?) => RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: ListView(
              padding: AleraTokens.pagePadding,
              children: <Widget>[
                const AleraNotice(
                  icon: AleraIcons.info,
                  message: 'Agents exchanged these messages. This view is read only.',
                ),
                const SizedBox(height: AleraTokens.spaceMd),
                for (final message in value.messages)
                  _ConversationMessageCard(message: message, labels: labels),
              ],
            ),
          ),
        },
      ),
    );
  }
}

class const _ConversationMessageCard({
  required final AgentConversationMessage message,
  required final Map<String, String> labels,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = agentConversationHandleLabel(message.from, labels);
    final to = agentConversationHandleLabel(message.to, labels);
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '$from to $to',
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                AleraBadge(label: message.typeLabel),
              ],
            ),
            if (message.subject.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space4),
              Text(message.subject, style: theme.textTheme.titleSmall),
            ],
            if (message.body.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space4),
              SelectableText(message.body, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: AleraTokens.space4),
            Text(
              inboxAgeLabel(message.createdAt, DateTime.now().toUtc()),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
