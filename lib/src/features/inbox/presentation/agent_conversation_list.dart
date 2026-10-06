import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/features/inbox/application/conversation_participant_labels.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/conversation_models.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/presentation/inbox_labels.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page_continuation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Threads between agents, most recent activity first. Read-only.
class AgentConversationListPane extends ConsumerStatefulWidget {
  const AgentConversationListPane({super.key, this.now});

  /// Fixed clock for tests; defaults to the wall clock.
  final DateTime? now;

  @override
  ConsumerState<AgentConversationListPane> createState() =>
      _AgentConversationListPaneState();
}

class _AgentConversationListPaneState
    extends ConsumerState<AgentConversationListPane> {
  final _more = InboxPageContinuation<ConversationThread>(
    (thread) => thread.threadId,
  );

  Future<void> _loadMore(String? workspaceId, int before) async {
    final generation = _more.generation;
    setState(() {
      _more.loading = true;
      _more.error = null;
    });
    try {
      final page = await ref
          .read(inboxRepositoryProvider)
          .readConversations(workspaceId: workspaceId, before: before);
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
    final workspaces = ref.watch(conversationWorkspaceNamesProvider);
    final labels = ref.watch(conversationParticipantLabelsProvider);
    final page = ref.watch(
      agentConversationsProvider(workspaceId: location.conversationWorkspace),
    );
    _more.sync('${location.conversationWorkspace}', page.value);
    final items = _more.merge(
      page.value?.items ?? const <ConversationThread>[],
    );
    final cursor = _more.cursorAfter(page.value?.nextBefore);
    final workspaceIds =
        <String>{...workspaces.keys, ?location.conversationWorkspace}.toList()
          ..sort((a, b) => (workspaces[a] ?? a).compareTo(workspaces[b] ?? b));
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space8),
          child: AleraDropdownField<String?>(
            key: const ValueKey<String>('conversationWorkspaceFilter'),
            labelText: 'Workspace',
            value: location.conversationWorkspace,
            filterable: workspaceIds.length > 6,
            entries: <AleraDropdownFieldEntry<String?>>[
              const AleraDropdownFieldEntry<String?>(
                value: null,
                label: 'All Workspaces',
              ),
              for (final id in workspaceIds)
                AleraDropdownFieldEntry<String?>(
                  value: id,
                  label: workspaces[id] ?? id,
                ),
            ],
            onChanged: navigation.filterConversationWorkspace,
          ),
        ),
        Expanded(
          child: page.hasError
              ? AleraEmptyState(
                  icon: AleraIcons.warning,
                  title: 'Conversations Unavailable',
                  message: inboxErrorMessage(page.error!),
                )
              : page.isLoading && !page.hasValue
              ? const AleraEmptyState(
                  loading: true,
                  message: 'Loading conversations...',
                )
              : items.isEmpty
              ? const AleraEmptyState(
                  icon: AleraIcons.comment,
                  title: 'No Agent Conversations',
                  message: 'Messages agents send each other with alera orchestration appear here. Task control such as dispatches and completions stays on the Run Board.',
                )
              : ListView.builder(
                  itemCount: items.length + (cursor == null ? 0 : 1),
                  itemBuilder: (context, index) => index == items.length
                      ? InboxLoadMoreButton(
                          loading: _more.loading,
                          error: _more.error == null
                              ? null
                              : inboxErrorMessage(_more.error!),
                          onPressed: () => _loadMore(
                            location.conversationWorkspace,
                            cursor!,
                          ),
                        )
                      : AgentConversationTile(
                          thread: items[index],
                          labels: labels,
                          workspaceName: workspaces[items[index].workspaceId],
                          selected:
                              items[index].threadId ==
                              location.selectedConversationId,
                          now: now ?? DateTime.now(),
                          onTap: () => navigation.selectConversation(
                            items[index].threadId,
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class const AgentConversationTile({
  super.key,
  required final ConversationThread thread,
  required final Map<String, String> labels,
  final String? workspaceName,
  required final bool selected,
  required final DateTime now,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final people = thread.participants
        .map((handle) => participantLabel(labels, handle))
        .join(', ');
    final count = thread.messageCount;
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
              child: Text(thread.subject, maxLines: 1, overflow: .ellipsis),
            ),
            if (thread.group) ...<Widget>[
              const SizedBox(width: AleraTokens.space6),
              const AleraBadge(label: 'Group', tone: AleraBadgeTone.info),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(people, maxLines: 1, overflow: .ellipsis, style: muted),
            Text(
              [
                '$count ${count == 1 ? 'message' : 'messages'}',
                ?workspaceName,
                inboxTimeLabel(thread.lastActivityAt, now),
              ].join(' · '),
              maxLines: 1,
              overflow: .ellipsis,
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}
