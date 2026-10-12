import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/chat/alera_message_bubble.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/presentation/question_follow_up_composer.dart';
import 'package:alera/src/features/inbox/presentation/question_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One question thread: every question and reply, plus a follow-up composer.
///
/// Replies are marked read only while this view is shown and the window is
/// visible and focused, and again when focus returns. Marking read reaches
/// every device, so a refresh in a hidden window must not do it.
class QuestionThreadDetail extends ConsumerStatefulWidget {
  const QuestionThreadDetail({super.key, required this.threadId, this.now});

  final String threadId;

  /// Fixed clock for tests; defaults to the wall clock.
  final DateTime? now;

  @override
  ConsumerState<QuestionThreadDetail> createState() =>
      _QuestionThreadDetailState();
}

class _QuestionThreadDetailState extends ConsumerState<QuestionThreadDetail> {
  StreamSubscription<bool>? _focusChanges;
  int? _acknowledgedRevision;

  @override
  void initState() {
    super.initState();
    _focusChanges = ref
        .read(inboxWindowFocusProvider)
        .changes
        .listen((focused) => focused ? _acknowledge() : null);
    ref.listenManual(
      inboxThreadDetailProvider(widget.threadId),
      (_, _) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _acknowledge()),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    unawaited(_focusChanges?.cancel());
    super.dispose();
  }

  void _acknowledge() {
    // Post-frame and focus callbacks can land after dispose; `ref` is unusable then.
    if (!mounted) return;
    final detail = ref.read(inboxThreadDetailProvider(widget.threadId)).value;
    if (detail == null ||
        detail.thread.unreadReplyCount == 0 ||
        detail.revision == _acknowledgedRevision ||
        !ref.read(inboxWindowFocusProvider).isForeground) {
      return;
    }
    _acknowledgedRevision = detail.revision;
    unawaited(
      ref
          .read(inboxRepositoryProvider)
          .markRead(widget.threadId)
          .catchError((Object _) => _acknowledgedRevision = null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    final detail = ref.watch(inboxThreadDetailProvider(threadId));
    if (detail.hasError && !detail.hasValue) {
      return AleraEmptyState(
        icon: AleraIcons.warning,
        title: 'Question Unavailable',
        message: inboxErrorMessage(detail.error!),
      );
    }
    final value = detail.value;
    if (value == null) {
      return const AleraEmptyState(
        loading: true,
        message: 'Loading question...',
      );
    }
    final now = widget.now ?? DateTime.now();
    final thread = value.thread;
    final hint = thread.status.open
        ? questionDeliveryHint(value.recipient.deliveryMode)
        : null;
    final header = <Widget>[
      QuestionThreadHeader(detail: value),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space4,
          ),
          child: AleraInlineNotice(tone: .warning, message: hint),
        ),
    ];
    final bubbles = <Widget>[
      for (final message in value.messages)
        _QuestionMessageBubble(
          message: message,
          inbox: thread.inbox,
          agent: inboxAgentLabel(thread.target.agent ?? value.recipient.agent),
          now: now,
        ),
    ];
    final composer = QuestionFollowUpComposer(
      key: ValueKey<String>('followUp:$threadId'),
      threadId: threadId,
      recipient: value.recipient,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        // Too short to pin the composer under a scrolling thread: everything
        // scrolls together so the composer stays reachable.
        if (constraints.maxHeight < _pinnedComposerMinHeight * scale) {
          return ListView(
            children: <Widget>[
              ...header,
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Column(crossAxisAlignment: .stretch, children: bubbles),
              ),
              const Divider(height: 1),
              composer,
            ],
          );
        }
        return Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            ...header,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AleraTokens.space12),
                children: bubbles,
              ),
            ),
            const Divider(height: 1),
            composer,
          ],
        );
      },
    );
  }
}

const double _pinnedComposerMinHeight = 480;

/// Subject, status, who was asked and how the question reaches them, plus
/// Mark Read and Cancel Question.
class const QuestionThreadHeader({
  super.key,
  required final InboxThreadDetail detail,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thread = detail.thread;
    final question = detail.latestQuestion;
    final target = thread.target;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final delivery = questionDeliveryLabel(questionThreadDeliveryMode(detail));
    final asked = <String>[
      if (thread.origin case final origin?) 'Asked from ${origin.label}',
      ?delivery,
    ].join(' · ');
    return Padding(
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
          Row(
            spacing: AleraTokens.space8,
            children: <Widget>[
              Expanded(
                child: Text(thread.subject, style: theme.textTheme.titleMedium),
              ),
              AleraBadge(label: thread.status.label, tone: thread.status.tone),
            ],
          ),
          Text(
            <String>[
              'To ${inboxAgentLabel(target.agent ?? detail.recipient.agent)}',
              ?target.tabTitle,
              ?target.workspaceName,
              'from ${thread.inbox}',
            ].join(' · '),
            style: muted,
          ),
          Row(
            spacing: AleraTokens.space8,
            children: <Widget>[
              Expanded(child: Text(asked, style: muted)),
              if (question?.status == InboxQuestionStatus.pending)
                TextButton(
                  key: const ValueKey<String>('inboxCancelQuestion'),
                  onPressed: () =>
                      unawaited(_cancel(context, ref, question!.id)),
                  child: const Text('Cancel Question'),
                ),
              if (thread.unreadReplyCount > 0)
                TextButton(
                  key: const ValueKey<String>('inboxMarkRead'),
                  onPressed: () => unawaited(
                    _run(
                      context,
                      () => ref
                          .read(inboxRepositoryProvider)
                          .markRead(thread.threadId),
                    ),
                  ),
                  child: const Text('Mark Read'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    String questionId,
  ) async {
    final repository = ref.read(inboxRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Cancel Question?',
        message: 'The agent has not received this question yet. Cancelling it means the agent never sees it.',
        confirmLabel: 'Cancel Question',
        cancelLabel: 'Keep Question',
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () => repository.cancel(questionId));
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(inboxErrorMessage(error))));
  }
}

class const _QuestionMessageBubble({
  required final InboxMessage message,
  required final String inbox,
  required final String agent,
  required final DateTime now,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final outgoing = message.kind == InboxMessageKind.question;
    final status = message.status;
    final expiry = status == InboxQuestionStatus.pending
        ? inboxExpiryLabel(message.expiresAt, now)
        : null;
    return AleraMessageBubble(
      heading: switch (message.kind) {
        .question => 'Question · $inbox',
        .reply => 'Reply · $agent',
        .message => 'Message · ${message.from}',
      },
      body: message.body,
      outgoing: outgoing,
      statusLabel: status?.label,
      statusTone: status?.tone ?? AleraBadgeTone.neutral,
      isNew: !outgoing && !message.read,
      timestamp: <String>[
        inboxTimeLabel(message.createdAt, now),
        ?expiry,
      ].where((part) => part.isNotEmpty).join(' · '),
    );
  }
}
