import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/infra/runtime_inbox_repository.dart';
import 'package:alera/src/features/inbox/presentation/inbox_labels.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page_continuation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filters plus the threads that match them, in the host's order: most
/// recent thread activity first.
class InboxThreadListPane extends ConsumerStatefulWidget {
  const InboxThreadListPane({super.key, this.now});

  /// Fixed clock for tests; defaults to the wall clock.
  final DateTime? now;

  @override
  ConsumerState<InboxThreadListPane> createState() =>
      _InboxThreadListPaneState();
}

class _InboxThreadListPaneState extends ConsumerState<InboxThreadListPane> {
  final _more = InboxPageContinuation<InboxThread>((thread) => thread.threadId);

  Future<void> _loadMore(InboxLocation location, int before) async {
    final generation = _more.generation;
    setState(() {
      _more.loading = true;
      _more.error = null;
    });
    try {
      final page = await ref
          .read(inboxRepositoryProvider)
          .readThreads(
            InboxThreadQuery(
              inbox: location.inboxFilter,
              status: location.statusFilter,
              before: before,
            ),
          );
      if (!mounted) return;
      setState(() => _more.append(generation, page.items, page.nextBefore));
    } on Object catch (error) {
      if (mounted) setState(() => _more.error = error);
    } finally {
      if (mounted) setState(() => _more.loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final location = ref.watch(inboxNavigationProvider);
    final navigation = ref.read(inboxNavigationProvider.notifier);
    final summary = ref.watch(inboxSummaryProvider).value;
    final threads = ref.watch(
      inboxThreadsProvider(
        inbox: location.inboxFilter,
        status: location.statusFilter,
      ),
    );
    final inboxes = <String>{
      ...?summary?.inboxes.map((entry) => entry.inbox),
      ?location.inboxFilter,
    }.toList()..sort();
    _more.sync(
      '${location.inboxFilter}|${location.statusFilter?.key}',
      threads.value,
    );
    final items = _more.merge(threads.value?.items ?? const <InboxThread>[]);
    final cursor = _more.cursorAfter(threads.value?.nextBefore);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space8),
          child: Row(
            spacing: AleraTokens.space8,
            children: <Widget>[
              Expanded(
                child: AleraDropdownField<String?>(
                  key: const ValueKey<String>('inboxFilterInbox'),
                  labelText: 'Inbox',
                  value: location.inboxFilter,
                  entries: <AleraDropdownFieldEntry<String?>>[
                    const AleraDropdownFieldEntry<String?>(
                      value: null,
                      label: 'All Inboxes',
                    ),
                    for (final inbox in inboxes)
                      AleraDropdownFieldEntry<String?>(
                        value: inbox,
                        label: inbox,
                      ),
                  ],
                  onChanged: navigation.filterInbox,
                ),
              ),
              Expanded(
                child: AleraDropdownField<InboxQuestionStatus?>(
                  key: const ValueKey<String>('inboxFilterStatus'),
                  labelText: 'Status',
                  value: location.statusFilter,
                  entries: <AleraDropdownFieldEntry<InboxQuestionStatus?>>[
                    const AleraDropdownFieldEntry<InboxQuestionStatus?>(
                      value: null,
                      label: 'Any Status',
                    ),
                    for (final status in InboxQuestionStatus.values)
                      AleraDropdownFieldEntry<InboxQuestionStatus?>(
                        value: status,
                        label: status.label,
                      ),
                  ],
                  onChanged: navigation.filterStatus,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: threads.hasError
              ? AleraEmptyState(
                  icon: AleraIcons.warning,
                  title: 'Inbox Unavailable',
                  message: inboxErrorMessage(threads.error!),
                )
              : threads.isLoading && !threads.hasValue
              ? const AleraEmptyState(
                  loading: true,
                  message: 'Loading questions...',
                )
              : items.isEmpty
              ? const AleraEmptyState(
                  icon: AleraIcons.inbox,
                  title: 'No Questions',
                  message: 'Questions asked from this app, a paired phone or alera inbox appear here with their replies.',
                )
              : ListView.builder(
                  itemCount: items.length + (cursor == null ? 0 : 1),
                  itemBuilder: (context, index) => index == items.length
                      ? InboxLoadMoreButton(
                          loading: _more.loading,
                          error: _more.error == null
                              ? null
                              : inboxErrorMessage(_more.error!),
                          onPressed: () => _loadMore(location, cursor!),
                        )
                      : InboxThreadTile(
                          thread: items[index],
                          selected:
                              items[index].threadId ==
                              location.selectedThreadId,
                          now: now ?? DateTime.now(),
                          onTap: () =>
                              navigation.selectThread(items[index].threadId),
                        ),
                ),
        ),
      ],
    );
  }
}

class const InboxThreadTile({
  super.key,
  required final InboxThread thread,
  required final bool selected,
  required final DateTime now,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final unread = thread.unreadReplyCount;
    final target = thread.target;
    final who = <String>[
      inboxAgentLabel(target.agent),
      ?target.tabTitle,
      ?target.workspaceName,
    ].join(' · ');
    return AleraActiveRail(
      active: selected,
      child: ListTile(
        selected: selected,
        selectedTileColor: AleraActiveRail.selectedColor,
        onTap: onTap,
        dense: true,
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                thread.subject,
                maxLines: 1,
                overflow: .ellipsis,
                style: unread > 0
                    ? theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: AleraTokens.space6),
            AleraBadge(
              label: thread.status.label,
              tone: inboxStatusTone(thread.status),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(who, maxLines: 1, overflow: .ellipsis, style: muted),
            Text(
              '${thread.inbox} · ${inboxTimeLabel(thread.lastActivityAt, now)}',
              maxLines: 1,
              overflow: .ellipsis,
              style: muted,
            ),
          ],
        ),
        trailing: unread == 0
            ? null
            : Semantics(
                label: '$unread unread ${unread == 1 ? 'reply' : 'replies'}',
                excludeSemantics: true,
                child: AleraBadge(
                  label: unread > 99 ? '99+' : '$unread',
                  tone: AleraBadgeTone.accent,
                ),
              ),
      ),
    );
  }
}
