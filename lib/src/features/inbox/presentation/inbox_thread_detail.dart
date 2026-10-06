import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/presentation/inbox_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One conversation: every question and reply, plus a follow-up composer.
///
/// Replies are marked read only while this view is shown and the window is
/// visible and focused, and again when focus returns. Marking read reaches
/// every device, so a refresh in a hidden window must not do it.
class InboxThreadDetailView extends ConsumerStatefulWidget {
  const InboxThreadDetailView({super.key, required this.threadId, this.now});

  final String threadId;

  /// Fixed clock for tests; defaults to the wall clock.
  final DateTime? now;

  @override
  ConsumerState<InboxThreadDetailView> createState() =>
      _InboxThreadDetailViewState();
}

class _InboxThreadDetailViewState extends ConsumerState<InboxThreadDetailView> {
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
    final now = widget.now;
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
      return const AleraEmptyState(loading: true, message: 'Loading thread...');
    }
    final clock = now ?? DateTime.now();
    final thread = value.thread;
    final hint = thread.status.open
        ? inboxDeliveryHint(value.recipient.deliveryMode)
        : null;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _ThreadHeader(detail: value),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
              vertical: AleraTokens.space4,
            ),
            child: AleraInlineNotice(tone: .warning, message: hint),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AleraTokens.space12),
            children: <Widget>[
              for (final message in value.messages)
                InboxMessageCard(
                  message: message,
                  inbox: thread.inbox,
                  now: clock,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        InboxFollowUpComposer(
          key: ValueKey<String>('followUp:$threadId'),
          threadId: threadId,
          enabled: value.recipient.sessionLive,
        ),
      ],
    );
  }
}

class _ThreadHeader extends ConsumerWidget {
  const _ThreadHeader({required this.detail});

  final InboxThreadDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thread = detail.thread;
    final question = detail.latestQuestion;
    final target = thread.target;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
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
            children: <Widget>[
              Expanded(
                child: Text(thread.subject, style: theme.textTheme.titleMedium),
              ),
              AleraBadge(
                label: thread.status.label,
                tone: inboxStatusTone(thread.status),
              ),
              if (question?.status == InboxQuestionStatus.pending)
                TextButton(
                  key: const ValueKey<String>('inboxCancelQuestion'),
                  onPressed: () => unawaited(
                    _run(context, () async {
                      await ref
                          .read(inboxRepositoryProvider)
                          .cancel(question!.id);
                    }),
                  ),
                  child: const Text('Cancel Question'),
                ),
              if (thread.unreadReplyCount > 0)
                TextButton(
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
          Text(
            [
              'To ${inboxAgentLabel(target.agent ?? detail.recipient.agent)}',
              ?target.tabTitle,
              ?target.workspaceName,
              'from ${thread.inbox}',
              if (thread.origin case final origin?) 'via ${origin.label}',
            ].join(' · '),
            style: muted,
          ),
        ],
      ),
    );
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

class const InboxMessageCard({
  super.key,
  required final InboxMessage message,
  required final String inbox,
  required final DateTime now,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outgoing = message.kind == InboxMessageKind.question;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final status = message.status;
    final expiry = status == InboxQuestionStatus.pending
        ? inboxExpiryLabel(message.expiresAt, now)
        : null;
    final heading = switch (message.kind) {
      .question => 'Question from $inbox',
      .reply => 'Reply',
      .message => 'Message',
    };
    return Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AleraTokens.space8),
        padding: const EdgeInsets.all(AleraTokens.space12),
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.chatBubbleMaxWidth,
        ),
        decoration: BoxDecoration(
          color: outgoing ? AleraTokens.surface : AleraTokens.surfaceElevated,
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
                Text(heading, style: theme.textTheme.labelMedium),
                if (status != null)
                  AleraBadge(
                    label: status.label,
                    tone: inboxStatusTone(status),
                  ),
                if (!outgoing && !message.read)
                  const AleraBadge(label: 'New', tone: AleraBadgeTone.accent),
                const Spacer(),
                Text(
                  [inboxTimeLabel(message.createdAt, now), ?expiry].join(' · '),
                  style: muted,
                ),
              ],
            ),
            SelectableText(message.body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Continues the thread with the same agent and inbox.
class InboxFollowUpComposer extends ConsumerStatefulWidget {
  const InboxFollowUpComposer({
    super.key,
    required this.threadId,
    required this.enabled,
  });

  final String threadId;

  /// False once the agent's terminal is gone; a follow-up would be refused.
  final bool enabled;

  @override
  ConsumerState<InboxFollowUpComposer> createState() =>
      _InboxFollowUpComposerState();
}

class _InboxFollowUpComposerState extends ConsumerState<InboxFollowUpComposer> {
  final _body = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _body.text.trim();
    if (body.isEmpty || _sending || !widget.enabled) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(inboxRepositoryProvider)
          .ask(InboxAskRequest(body: body, threadId: widget.threadId));
      _body.clear();
      if (mounted) setState(() => _sending = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = inboxErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          if (!widget.enabled)
            const AleraInlineNotice(
              message: 'This agent\'s terminal is no longer running. Ask another agent from New Question.',
            ),
          if (_error != null) AleraInlineNotice(tone: .error, message: _error!),
          Row(
            crossAxisAlignment: .end,
            spacing: AleraTokens.space8,
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  key: const ValueKey<String>('inboxFollowUpBody'),
                  controller: _body,
                  hintText: 'Ask a follow-up question',
                  minLines: 1,
                  maxLines: 6,
                  enabled: widget.enabled && !_sending,
                  onCommandEnter: () => unawaited(_send()),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey<String>('inboxFollowUpSend'),
                onPressed: widget.enabled && !_sending
                    ? () => unawaited(_send())
                    : null,
                icon: const Icon(AleraIcons.send, size: AleraTokens.iconMd),
                label: const Text('Send Follow-Up'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
