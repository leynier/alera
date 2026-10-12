import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/presentation/ask_agent_dialog.dart';
import 'package:alera/src/features/inbox/presentation/question_status.dart';
import 'package:alera/src/features/inbox/presentation/question_thread_detail.dart';
import 'package:alera/src/features/inbox/presentation/questions_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reloads everything the Questions section shows.
void refreshQuestions(WidgetRef ref) {
  ref.invalidate(inboxSummaryProvider);
  ref.invalidate(inboxThreadsProvider);
  ref.invalidate(inboxThreadDetailProvider);
  ref.invalidate(inboxTargetsProvider);
  ref.invalidate(inboxDeliverySupportedProvider);
}

/// The Questions section of Activity: questions asked to agents from outside
/// their terminals, and the replies. Messages between run agents live in
/// each run's Timeline.
class QuestionsSection extends ConsumerStatefulWidget {
  const QuestionsSection({super.key});

  @override
  ConsumerState<QuestionsSection> createState() => _QuestionsSectionState();
}

class _QuestionsSectionState extends ConsumerState<QuestionsSection> {
  int _handledCompose = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCompose());
  }

  void _maybeCompose() {
    if (!mounted) return;
    final location = ref.read(activityNavigationProvider).questions;
    final request = location.compose;
    if (request == null || location.composeSequence == _handledCompose) return;
    _handledCompose = location.composeSequence;
    ref.read(activityNavigationProvider.notifier).consumeCompose();
    unawaited(showAskAgentDialog(context, targetHandle: request.targetHandle));
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
      ref.read(activityNavigationProvider.notifier).filterInbox(null);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(inboxErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      activityNavigationProvider.select(
        (value) => value.questions.composeSequence,
      ),
      (_, _) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCompose()),
    );
    final location = ref.watch(
      activityNavigationProvider.select((value) => value.questions),
    );
    final navigation = ref.read(activityNavigationProvider.notifier);
    final summary = ref.watch(inboxSummaryProvider);
    final updateRequired = summary.error is InboxUpdateRequired;
    // The turn-end caption is for hosts known to lack `inboxV2`; while the
    // capability is unknown neither the caption nor the choice shows.
    final legacyDelivery =
        ref.watch(inboxDeliverySupportedProvider).value == false;
    final selected = location.selectedThreadId;
    const Widget master = QuestionsList();
    final Widget detail = selected == null
        ? const AleraEmptyState(
            icon: AleraIcons.inbox,
            title: 'Select A Question',
            message: 'Read replies, follow up with the same agent, or cancel a question it has not received yet.',
          )
        : QuestionThreadDetail(
            key: ValueKey<String>(selected),
            threadId: selected,
          );
    final purgeTarget = location.inboxFilter;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (purgeTarget != null)
            AleraHorizontalScrollView(
              child: Row(
                children: <Widget>[
                  TextButton.icon(
                    key: const ValueKey<String>('inboxPurge'),
                    onPressed: () => unawaited(_purge(purgeTarget)),
                    icon: const Icon(AleraIcons.delete),
                    label: const Text('Purge Inbox'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AleraTokens.space8),
          if (updateRequired)
            const Expanded(
              child: AleraEmptyState(
                icon: AleraIcons.inbox,
                title: 'Questions Unavailable',
                message: 'Update the runtime to use the inbox.',
              ),
            )
          else ...<Widget>[
            if (legacyDelivery)
              Text(
                questionLegacyDeliveryCaption,
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
                          onPressed: () => navigation.selectThread(null),
                          icon: const Icon(AleraIcons.back),
                          label: const Text('Back To Questions'),
                        ),
                        Expanded(child: detail),
                      ],
                    );
                  }
                  return AleraMasterDetail(
                    masterTitle: 'Questions',
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
    );
  }
}
