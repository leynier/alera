import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/presentation/agent_conversation_detail.dart';
import 'package:alera/src/features/inbox/presentation/agent_conversation_list.dart';
import 'package:alera/src/features/inbox/presentation/inbox_composer_dialog.dart';
import 'package:alera/src/features/inbox/presentation/inbox_thread_detail.dart';
import 'package:alera/src/features/inbox/presentation/inbox_thread_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Questions asked to agents from outside their terminals, and the replies.
/// Opened like the Run Board: the workbench stays mounted underneath.
class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key, this.onReturnToWorkspace});

  final VoidCallback? onReturnToWorkspace;

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  int _handledCompose = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCompose());
  }

  void _maybeCompose() {
    if (!mounted) return;
    final location = ref.read(inboxNavigationProvider);
    final request = location.compose;
    if (request == null || location.composeSequence == _handledCompose) return;
    _handledCompose = location.composeSequence;
    ref.read(inboxNavigationProvider.notifier).consumeCompose();
    unawaited(
      showInboxComposerDialog(context, targetHandle: request.targetHandle),
    );
  }

  Future<void> _purge(String inbox) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Purge Inbox?',
        message:
            'Every question and reply of $inbox is deleted from this runtime, on every device.',
        confirmLabel: 'Purge',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(inboxRepositoryProvider).purge(inbox);
      ref.read(inboxNavigationProvider.notifier).filterInbox(null);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(inboxErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      inboxNavigationProvider.select((value) => value.composeSequence),
      (_, _) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCompose()),
    );
    final location = ref.watch(inboxNavigationProvider);
    final navigation = ref.read(inboxNavigationProvider.notifier);
    final summary = ref.watch(inboxSummaryProvider);
    final updateRequired = summary.error is InboxUpdateRequired;
    final conversations = location.view == InboxView.conversations;
    final selected = conversations
        ? location.selectedConversationId
        : location.selectedThreadId;
    final Widget master = conversations
        ? const AgentConversationListPane()
        : const InboxThreadListPane();
    final Widget detail = switch ((conversations, selected)) {
      (true, null) => const AleraEmptyState(
        icon: AleraIcons.comment,
        title: 'Select A Conversation',
        message: 'Follow what agents tell each other. This view is read-only.',
      ),
      (false, null) => const AleraEmptyState(
        icon: AleraIcons.inbox,
        title: 'Select A Question',
        message: 'Read replies, follow up with the same agent, or cancel a question it has not received yet.',
      ),
      (true, final String id) => AgentConversationDetailView(
        key: ValueKey<String>('conversation:$id'),
        threadId: id,
      ),
      (false, final String id) => InboxThreadDetailView(
        key: ValueKey<String>(id),
        threadId: id,
      ),
    };
    final purgeTarget = conversations ? null : location.inboxFilter;
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Wrap(
              spacing: AleraTokens.space12,
              runSpacing: AleraTokens.space8,
              crossAxisAlignment: .center,
              children: <Widget>[
                const AleraAppMenuButton(),
                Text('Inbox', style: Theme.of(context).textTheme.titleLarge),
                AleraSegmentedButton<InboxView>(
                  key: const ValueKey<String>('inboxViewSwitch'),
                  dense: true,
                  selected: location.view,
                  onSelectionChanged: navigation.showView,
                  segments: const <ButtonSegment<InboxView>>[
                    ButtonSegment<InboxView>(
                      value: InboxView.questions,
                      label: Text('Questions'),
                    ),
                    ButtonSegment<InboxView>(
                      value: InboxView.conversations,
                      label: Text('Agent Conversations'),
                    ),
                  ],
                ),
                FilledButton.icon(
                  key: const ValueKey<String>('inboxNewQuestion'),
                  onPressed: updateRequired
                      ? null
                      : () => unawaited(showInboxComposerDialog(context)),
                  icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
                  label: const Text('New Question'),
                ),
                TextButton.icon(
                  onPressed: widget.onReturnToWorkspace ?? navigation.close,
                  icon: const Icon(AleraIcons.back),
                  label: const Text('Return To Workspace'),
                ),
                if (purgeTarget != null)
                  TextButton.icon(
                    key: const ValueKey<String>('inboxPurge'),
                    onPressed: () => unawaited(_purge(purgeTarget)),
                    icon: const Icon(AleraIcons.delete),
                    label: const Text('Purge Inbox'),
                  ),
                IconButton(
                  tooltip: 'Refresh Inbox',
                  icon: const Icon(AleraIcons.refresh),
                  onPressed: () {
                    ref.invalidate(inboxSummaryProvider);
                    ref.invalidate(inboxThreadsProvider);
                    ref.invalidate(inboxThreadDetailProvider);
                    ref.invalidate(agentConversationsProvider);
                    ref.invalidate(agentConversationProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
            if (updateRequired)
              const Expanded(
                child: AleraEmptyState(
                  icon: AleraIcons.inbox,
                  title: 'Inbox Unavailable',
                  message: 'Update the runtime to use the inbox.',
                ),
              )
            else ...<Widget>[
              Text(
                'Agents receive a question when they finish their turn and answer with alera orchestration reply. Undelivered questions expire after 5 hours by default; history is kept for 7 days.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
              ),
              if (summary.hasError) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                AleraInlineNotice(
                  tone: .warning,
                  message: inboxErrorMessage(summary.error!),
                ),
              ],
              const SizedBox(height: AleraTokens.space8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    if (constraints.maxWidth <
                        AleraTokens.wideContentBreakpoint * scale) {
                      if (selected == null) return master;
                      return Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: () => conversations
                                ? navigation.selectConversation(null)
                                : navigation.selectThread(null),
                            icon: const Icon(AleraIcons.back),
                            label: Text(
                              conversations
                                  ? 'Back To Conversations'
                                  : 'Back To Questions',
                            ),
                          ),
                          Expanded(child: detail),
                        ],
                      );
                    }
                    return AleraMasterDetail(
                      masterTitle: conversations
                          ? 'Conversations'
                          : 'Questions',
                      masterWidth: AleraTokens.sidebarDefaultWidth,
                      masterMaxWidth: AleraTokens.masterDetailMaxWidth,
                      master: master,
                      detail: detail,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
