import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_delivery_labels.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_follow_up_composer.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One conversation with an agent: every question and reply, how the latest
/// question reaches the agent, and a follow-up composer.
///
/// Replies are acknowledged only while this screen is shown and the app is in
/// the foreground, at most once per thread revision, so a refresh that runs in
/// the background never marks them read on every device.
class const InboxThreadScreen({
  super.key,
  required final String hostId,
  required final String threadId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<InboxThreadScreen> createState() => _InboxThreadScreenState();
}

class _InboxThreadScreenState extends ConsumerState<InboxThreadScreen> {
  int? _acknowledgedRevision;

  void _acknowledgeIfSeen(InboxThreadDetail? detail) {
    final foreground =
        ref.read(appLifecycleControllerProvider) == AppLifecycleState.resumed;
    final shown = ModalRoute.of(context)?.isCurrent ?? true;
    if (detail == null ||
        !foreground ||
        !shown ||
        detail.thread.unreadReplyCount == 0 ||
        _acknowledgedRevision == detail.revision) {
      return;
    }
    _acknowledgedRevision = detail.revision;
    unawaited(_acknowledge());
  }

  Future<void> _acknowledge() async {
    try {
      final repository = await ref.read(
        mobileInboxRepositoryProvider(widget.hostId).future,
      );
      await repository.markRead(widget.threadId);
    } on Object {
      // The next revision or the next resume tries again.
      _acknowledgedRevision = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostId = widget.hostId;
    final threadId = widget.threadId;
    final detail = ref.watch(mobileInboxThreadDetailProvider(hostId, threadId));
    final value = detail.value;
    // Rebuilds on resume as well, which re-acknowledges what arrived while the
    // app was in the background.
    ref.watch(appLifecycleControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _acknowledgeIfSeen(value);
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(
          value?.thread.subject ?? 'Conversation',
          maxLines: 1,
          overflow: .ellipsis,
        ),
      ),
      body: SafeArea(
        child: switch (detail) {
          AsyncValue(value: null, hasError: true, :final error) =>
            AleraEmptyState(
              icon: AleraIcons.inbox,
              title: 'Conversation Unavailable',
              message: 'The host could not load this conversation.',
              detail: inboxErrorMessage(error),
              action: TextButton(
                onPressed: () => ref.invalidate(
                  mobileInboxThreadDetailProvider(hostId, threadId),
                ),
                child: const Text('Retry'),
              ),
            ),
          AsyncValue(value: null) => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: AleraTokens.pagePadding,
                  children: <Widget>[
                    _ThreadHeader(hostId: hostId, detail: value!),
                    const SizedBox(height: AleraTokens.spaceMd),
                    for (final message in value.messages)
                      _MessageCard(message: message, thread: value.thread),
                  ],
                ),
              ),
              InboxFollowUpComposer(
                hostId: hostId,
                threadId: threadId,
                recipient: value.recipient,
              ),
            ],
          ),
        },
      ),
    );
  }
}

class const _ThreadHeader({
  required final String hostId,
  required final InboxThreadDetail detail,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thread = detail.thread;
    final latest = detail.latestQuestion;
    final pending = latest?.status == InboxQuestionStatus.pending;
    final expiry = pending
        ? inboxExpiryLabel(latest?.expiresAt, DateTime.now().toUtc())
        : null;
    final delivery = inboxThreadDeliveryLabel(inboxThreadDeliveryMode(detail));
    final recipientMode = detail.recipient?.deliveryMode;
    final deliveryHint =
        thread.status == InboxQuestionStatus.answered || recipientMode == null
        ? null
        : inboxDeliveryHint(recipientMode);
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AleraBadge(
                  label: thread.status.label,
                  tone: inboxStatusTone(thread.status),
                ),
                if (expiry != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  Text(expiry, style: theme.textTheme.labelSmall),
                ],
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              'To ${thread.recipientLabel}',
              style: theme.textTheme.bodyMedium,
            ),
            if (thread.target.workspaceName case final workspace?)
              Text(
                'Workspace $workspace',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            Text(
              'From ${thread.inbox}${thread.origin == null ? '' : ' via ${thread.origin!.label}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (delivery != null)
              Text(
                delivery,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            const SizedBox(height: AleraTokens.space8),
            AleraNotice(
              icon: AleraIcons.info,
              message: deliveryHint == null
                  ? inboxStatusHint(thread.status)
                  : '${inboxStatusHint(thread.status)} $deliveryHint',
            ),
            if (pending && latest != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => unawaited(_cancel(context, ref, latest.id)),
                  icon: const Icon(AleraIcons.close),
                  label: const Text('Cancel Question'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    String questionId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Cancel Question',
        message: 'The agent will not receive this question.',
        confirmLabel: 'Cancel Question',
        cancelLabel: 'Keep',
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = await ref.read(
        mobileInboxRepositoryProvider(hostId).future,
      );
      await repository.cancel(questionId);
    } on Object catch (error, stackTrace) {
      showActionFailure(
        messenger,
        action: 'cancel the question',
        error: error,
        stackTrace: stackTrace,
        message: actionFailureMessage(
          'cancel the question',
          inboxErrorMessage(error),
        ),
      );
    }
  }
}

class const _MessageCard({
  required final InboxMessage message,
  required final InboxThread thread,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = message.isQuestion;
    final author = question ? thread.inbox : thread.recipientLabel;
    final title = switch (message.kind) {
      InboxMessageKind.question => 'Question',
      InboxMessageKind.reply => 'Reply',
      InboxMessageKind.message => 'Message',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Align(
        alignment: question
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Card(
          color: question ? AleraTokens.surfaceVariant : null,
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.labelMedium),
                    if (message.status case final status?) ...<Widget>[
                      const SizedBox(width: AleraTokens.space8),
                      AleraBadge(
                        label: status.label,
                        tone: inboxStatusTone(status),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AleraTokens.space4),
                SelectableText(message.body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  '$author · ${inboxAgeLabel(message.createdAt, DateTime.now().toUtc())}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
