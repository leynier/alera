import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_compose_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_labels.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/load_more_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Questions this host's agents were asked from outside a terminal, from the
/// phone, the desktop or the command line, with their replies.
class const InboxScreen({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(mobileInboxSummaryProvider(hostId)).value;
    final filters = ref.watch(mobileInboxListControllerProvider(hostId));
    final threadsProvider = mobileInboxThreadsProvider(
      hostId,
      inbox: filters.inbox,
      status: filters.status,
    );
    final threads = ref.watch(threadsProvider);
    final controller = ref.read(
      mobileInboxListControllerProvider(hostId).notifier,
    );
    final all = threads.value?.items ?? const <InboxThread>[];
    final visible = visibleInboxThreads(all, filters);
    final inboxes = <String>{
      for (final entry in summary ?? const <InboxSummaryEntry>[]) entry.inbox,
      for (final thread in all) thread.inbox,
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'More Actions',
            onSelected: (inbox) => unawaited(_purge(context, ref, inbox)),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final inbox in inboxes)
                PopupMenuItem<String>(
                  value: inbox,
                  height: AleraTokens.minTapTarget,
                  child: Text('Purge $inbox'),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_compose(context)),
        icon: const Icon(AleraIcons.send),
        label: const Text('Ask Agent'),
      ),
      body: SafeArea(
        child: switch (threads) {
          AsyncValue(value: null, hasError: true, :final error) =>
            AleraEmptyState(
              icon: AleraIcons.inbox,
              title: 'Inbox Unavailable',
              message: 'The host could not load the inbox.',
              detail: '$error',
              action: TextButton(
                onPressed: () => ref.invalidate(threadsProvider),
                child: const Text('Retry'),
              ),
            ),
          AsyncValue(value: null) => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => RefreshIndicator(
            onRefresh: () => ref.refresh(threadsProvider.future),
            child: ListView(
              padding: AleraTokens.pagePadding,
              children: <Widget>[
                _InboxFilters(
                  inboxes: inboxes,
                  filters: filters,
                  onInbox: controller.setInbox,
                  onStatus: controller.setStatus,
                ),
                const SizedBox(height: AleraTokens.spaceMd),
                if (visible.isEmpty)
                  AleraEmptyState(
                    icon: AleraIcons.inbox,
                    message: filters.isFiltered
                        ? 'No questions match these filters.'
                        : 'No questions yet. Ask an agent to start a conversation.',
                    action: filters.isFiltered
                        ? TextButton(
                            onPressed: controller.clear,
                            child: const Text('Clear Filters'),
                          )
                        : null,
                  )
                else
                  for (final thread in visible)
                    InboxThreadRow(
                      thread: thread,
                      onOpen: () => unawaited(
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => InboxThreadScreen(
                              hostId: hostId,
                              threadId: thread.threadId,
                            ),
                          ),
                        ),
                      ),
                    ),
                if (threads.value?.nextBefore != null)
                  LoadMoreButton(
                    onLoad: ref.read(threadsProvider.notifier).loadMore,
                  ),
              ],
            ),
          ),
        },
      ),
    );
  }

  Future<void> _compose(BuildContext context) async {
    final threadId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => InboxComposeScreen(hostId: hostId),
      ),
    );
    if (threadId == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InboxThreadScreen(hostId: hostId, threadId: threadId),
      ),
    );
  }

  Future<void> _purge(BuildContext context, WidgetRef ref, String inbox) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Purge Inbox',
        message:
            'Delete every question and reply of $inbox on this host. This cannot be undone.',
        confirmLabel: 'Purge',
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = await ref.read(
        mobileInboxRepositoryProvider(hostId).future,
      );
      await repository.purge(inbox);
      ref.read(mobileInboxListControllerProvider(hostId).notifier).clear();
      messenger.showSnackBar(SnackBar(content: Text('Purged $inbox')));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not purge $inbox: $error')),
      );
    }
  }
}

class const _InboxFilters({
  required final List<String> inboxes,
  required final MobileInboxListState filters,
  required final ValueChanged<String?> onInbox,
  required final ValueChanged<InboxQuestionStatus?> onStatus,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AleraTokens.space8,
      runSpacing: AleraTokens.space8,
      children: <Widget>[
        if (inboxes.length > 1)
          for (final inbox in inboxes)
            AleraChip(
              label: inbox,
              leading: filters.inbox == inbox ? AleraIcons.check : null,
              onTap: () => onInbox(filters.inbox == inbox ? null : inbox),
            ),
        for (final status in InboxQuestionStatus.filterable)
          AleraChip(
            label: status.label,
            leading: filters.status == status ? AleraIcons.check : null,
            onTap: () => onStatus(filters.status == status ? null : status),
          ),
      ],
    );
  }
}

/// One conversation: subject, recipient, status and unread replies.
class const InboxThreadRow({
  super.key,
  required final InboxThread thread,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = thread.unreadReplyCount;
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
                      thread.subject,
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread > 0 ? .w700 : null,
                      ),
                    ),
                  ),
                  if (unread > 0) ...<Widget>[
                    const SizedBox(width: AleraTokens.space8),
                    AleraBadge(
                      label: unread == 1
                          ? '1 New Reply'
                          : '$unread New Replies',
                      tone: AleraBadgeTone.accent,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                thread.recipientLabel,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
              Row(
                children: <Widget>[
                  AleraBadge(
                    label: thread.status.label,
                    tone: inboxStatusTone(thread.status),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      '${thread.inbox} · ${inboxAgeLabel(thread.lastActivityAt, DateTime.now().toUtc())}',
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
