import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/agent_conversation_models.dart';
import 'package:alera_mobile/src/features/inbox/presentation/agent_conversation_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_labels.dart';
import 'package:alera_mobile/src/features/inbox/presentation/load_more_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only list of what agents on this host say to each other, filterable by
/// workspace.
class const AgentConversationsView({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(
      mobileAgentConversationWorkspaceProvider(hostId),
    );
    final provider = mobileAgentConversationsProvider(
      hostId,
      workspaceId: workspaceId,
    );
    final conversations = ref.watch(provider);
    final labels =
        ref.watch(mobileInboxHandleLabelsProvider(hostId)).value ??
        const <String, String>{};
    final workspaceNames =
        ref.watch(mobileInboxWorkspaceNamesProvider(hostId)).value ??
        const <String, String>{};
    final selectWorkspace = ref
        .read(mobileAgentConversationWorkspaceProvider(hostId).notifier)
        .select;
    return switch (conversations) {
      AsyncValue(value: null, hasError: true, :final error) => AleraEmptyState(
        icon: AleraIcons.comment,
        title: 'Conversations Unavailable',
        message: 'The host could not load agent conversations.',
        detail: '$error',
        action: TextButton(
          onPressed: () => ref.invalidate(provider),
          child: const Text('Retry'),
        ),
      ),
      AsyncValue(value: null) => const Center(
        child: CircularProgressIndicator(),
      ),
      AsyncValue(
        value: AgentConversationPage(:final items, :final nextBefore)?,
      ) =>
        RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: ListView(
            padding: AleraTokens.pagePadding,
            children: <Widget>[
              if (workspaceNames.length > 1 || workspaceId != null) ...<Widget>[
                Wrap(
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: <Widget>[
                    for (final MapEntry(key: id, value: name)
                        in workspaceNames.entries)
                      AleraChip(
                        label: name,
                        leading: workspaceId == id ? AleraIcons.check : null,
                        onTap: () =>
                            selectWorkspace(workspaceId == id ? null : id),
                      ),
                  ],
                ),
                const SizedBox(height: AleraTokens.spaceMd),
              ],
              if (items.isEmpty)
                AleraEmptyState(
                  icon: AleraIcons.comment,
                  message: workspaceId == null
                      ? 'Agents have not messaged each other yet.'
                      : 'No agent conversations in this workspace.',
                  action: workspaceId == null
                      ? null
                      : TextButton(
                          onPressed: () => selectWorkspace(null),
                          child: const Text('Clear Filters'),
                        ),
                )
              else
                for (final conversation in items)
                  AgentConversationRow(
                    conversation: conversation,
                    labels: labels,
                    workspaceName: workspaceNames[conversation.workspaceId],
                    onOpen: () => unawaited(
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => AgentConversationScreen(
                            hostId: hostId,
                            conversation: conversation,
                          ),
                        ),
                      ),
                    ),
                  ),
              if (nextBefore != null)
                LoadMoreButton(onLoad: ref.read(provider.notifier).loadMore),
            ],
          ),
        ),
    };
  }
}

/// One conversation: subject, who takes part, message count and age.
class const AgentConversationRow({
  super.key,
  required final AgentConversation conversation,
  required final Map<String, String> labels,
  required final VoidCallback onOpen,
  final String? workspaceName,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participants = conversation.participants
        .map((handle) => agentConversationHandleLabel(handle, labels))
        .join(', ');
    final count = conversation.messageCount;
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      conversation.subject.isEmpty
                          ? 'Conversation'
                          : conversation.subject,
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (conversation.group) ...<Widget>[
                    const SizedBox(width: AleraTokens.space8),
                    const AleraBadge(label: 'Group', tone: AleraBadgeTone.info),
                  ],
                ],
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                participants,
                maxLines: 2,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                <String>[
                  count == 1 ? '1 message' : '$count messages',
                  ?workspaceName,
                  inboxAgeLabel(
                    conversation.lastActivityAt,
                    DateTime.now().toUtc(),
                  ),
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
