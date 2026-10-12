import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/presentation/question_delivery_choice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Continues a question thread with the same agent and inbox.
class QuestionFollowUpComposer extends ConsumerStatefulWidget {
  const QuestionFollowUpComposer({
    super.key,
    required this.threadId,
    required this.recipient,
  });

  final String threadId;

  /// The agent as the host sees it now; a follow-up to a terminal that is
  /// gone would be refused.
  final InboxRecipient recipient;

  @override
  ConsumerState<QuestionFollowUpComposer> createState() =>
      _QuestionFollowUpComposerState();
}

class _QuestionFollowUpComposerState
    extends ConsumerState<QuestionFollowUpComposer> {
  final _body = TextEditingController();
  InboxDelivery _delivery = InboxDelivery.now;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _enabled => widget.recipient.sessionLive;

  Future<void> _send({required bool deliverySupported}) async {
    final body = _body.text.trim();
    if (body.isEmpty || _sending || !_enabled) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(inboxRepositoryProvider)
          .ask(
            InboxAskRequest(
              body: body,
              threadId: widget.threadId,
              delivery: deliverySupported
                  ? effectiveQuestionDelivery(
                      _delivery,
                      widget.recipient.deliveryMode,
                    )
                  : null,
            ),
          );
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
    final deliverySupported =
        ref.watch(inboxDeliverySupportedProvider).value ?? false;
    final enabled = _enabled && !_sending;
    void send() => unawaited(_send(deliverySupported: deliverySupported));
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          if (!_enabled)
            const AleraInlineNotice(
              message: 'This agent\'s terminal is no longer running. Ask another agent with Ask Agent.',
            ),
          if (_error != null) AleraInlineNotice(tone: .error, message: _error!),
          AleraTextField(
            key: const ValueKey<String>('inboxFollowUpBody'),
            controller: _body,
            hintText: 'Ask a follow-up question',
            minLines: 1,
            maxLines: 6,
            enabled: enabled,
            onCommandEnter: send,
          ),
          if (deliverySupported)
            QuestionDeliveryChoice(
              key: const ValueKey<String>('inboxFollowUpDelivery'),
              selected: _delivery,
              targetMode: widget.recipient.deliveryMode,
              enabled: enabled,
              onChanged: (value) => setState(() => _delivery = value),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: const ValueKey<String>('inboxFollowUpSend'),
              onPressed: enabled ? send : null,
              icon: const Icon(AleraIcons.send, size: AleraTokens.iconMd),
              label: Text(_sending ? 'Sending...' : 'Send Follow-Up'),
            ),
          ),
        ],
      ),
    );
  }
}
