import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/inbox/application/conversation_participant_labels.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/conversation_models.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/presentation/inbox_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every message of an agent conversation in order. Read-only.
class AgentConversationDetailView extends ConsumerWidget {
  const AgentConversationDetailView({
    super.key,
    required this.threadId,
    this.now,
  });

  final String threadId;

  /// Fixed clock for tests; defaults to the wall clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(agentConversationProvider(threadId));
    final labels = ref.watch(conversationParticipantLabelsProvider);
    if (detail.hasError && !detail.hasValue) {
      return AleraEmptyState(
        icon: AleraIcons.warning,
        title: 'Conversation Unavailable',
        message: inboxErrorMessage(detail.error!),
      );
    }
    final value = detail.value;
    if (value == null) {
      return const AleraEmptyState(
        loading: true,
        message: 'Loading conversation...',
      );
    }
    final clock = now ?? DateTime.now();
    final subject = value.messages.firstOrNull?.subject ?? '';
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space12,
            AleraTokens.space12,
            AleraTokens.space12,
            AleraTokens.space4,
          ),
          child: Column(
            crossAxisAlignment: .start,
            spacing: AleraTokens.space4,
            children: <Widget>[
              Text(subject, style: Theme.of(context).textTheme.titleMedium),
              Text(
                'Read-only. Agents send these with alera orchestration; opening them changes nothing for the agents.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AleraTokens.space12),
            children: <Widget>[
              for (final message in value.messages)
                AgentConversationMessageCard(
                  message: message,
                  from: participantLabel(labels, message.from),
                  to: participantLabel(labels, message.to),
                  now: clock,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class const AgentConversationMessageCard({
  super.key,
  required final ConversationMessage message,
  required final String from,
  required final String to,
  required final DateTime now,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: AleraTokens.space6,
        children: <Widget>[
          Row(
            spacing: AleraTokens.space6,
            children: <Widget>[
              Expanded(
                child: Text(
                  '$from → $to',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              AleraBadge(label: message.typeLabel),
              Text(
                inboxTimeLabel(message.createdAt, now),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
          SelectableText(message.body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
