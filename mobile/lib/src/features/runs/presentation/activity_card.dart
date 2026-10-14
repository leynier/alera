import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/runs/application/activity_providers.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The host dashboard's way into Activity: one row per part, each with what
/// needs the user there.
class const ActivityCard({
  super.key,
  required final String hostId,
  final bool supportsRuns = false,
  final bool supportsInbox = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    void open(ActivitySection section) =>
        unawaited(openActivity(context, hostId: hostId, section: section));
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  AleraIcons.workspaceChildren,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Text('Activity', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            if (supportsRuns)
              _ActivityRow(
                section: ActivitySection.runs,
                icon: AleraIcons.workspaceChildren,
                count: ref.watch(mobileRunAttentionCountProvider(hostId)).value,
                countLabel: (count) => '$count Need Attention',
                description: 'Approve plans and gates, follow and cancel runs.',
                onOpen: () => open(ActivitySection.runs),
              ),
            if (supportsInbox)
              _ActivityRow(
                section: ActivitySection.questions,
                icon: AleraIcons.inbox,
                count: ref
                    .watch(mobileQuestionUnreadCountProvider(hostId))
                    .value,
                countLabel: (count) =>
                    count == 1 ? '1 New Reply' : '$count New Replies',
                description: 'Ask agents questions and read their replies.',
                onOpen: () => open(ActivitySection.questions),
              ),
            _ActivityRow(
              section: ActivitySection.automations,
              icon: AleraIcons.sync,
              count: ref
                  .watch(mobileAutomationAttentionCountProvider(hostId))
                  .value,
              countLabel: (count) => '$count Need Attention',
              description: 'View schedules and start approved runs.',
              onOpen: () => open(ActivitySection.automations),
            ),
            if (ref.watch(mobileChatTasksSupportedProvider(hostId)).value ??
                false)
              _ActivityRow(
                section: ActivitySection.chatTasks,
                icon: AleraIcons.agent,
                count: ref
                    .watch(mobileChatTaskAttentionCountProvider(hostId))
                    .value,
                countLabel: (count) => '$count Need Attention',
                description:
                    'Delegate tasks to agent chats and follow their results.',
                onOpen: () => open(ActivitySection.chatTasks),
              ),
          ],
        ),
      ),
    );
  }
}

class const _ActivityRow({
  required final ActivitySection section,
  required final IconData icon,
  required final int? count,
  required final String Function(int count) countLabel,
  required final String description,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pending = count ?? 0;
    return ListTile(
      key: ValueKey<String>('activity-row-${section.name}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: AleraTokens.minTapTarget,
      leading: Icon(icon),
      title: Text(section.label),
      subtitle: Text(description),
      trailing: Row(
        mainAxisSize: .min,
        children: <Widget>[
          if (pending > 0)
            AleraBadge(
              label: countLabel(pending),
              tone: section == ActivitySection.questions
                  ? AleraBadgeTone.accent
                  : AleraBadgeTone.attention,
            ),
          IconButton(
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Open ${section.label}',
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}
