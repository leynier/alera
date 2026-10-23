import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_delivery_choice.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_delivery_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Continues a question thread with the same agent and inbox. Hosts with
/// `inboxV2` also offer when to deliver it.
class const InboxFollowUpComposer({
  super.key,
  required final String hostId,
  required final String threadId,

  /// The agent as the host sees it now; a follow-up to a terminal that is
  /// gone would be refused. Older hosts may omit it.
  final InboxRecipient? recipient,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<InboxFollowUpComposer> createState() =>
      _InboxFollowUpComposerState();
}

class _InboxFollowUpComposerState extends ConsumerState<InboxFollowUpComposer> {
  final TextEditingController _controller = TextEditingController();
  InboxDelivery _delivery = InboxDelivery.now;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _live => widget.recipient?.sessionLive ?? true;

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending || !_live) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = await ref.read(
        mobileInboxRepositoryProvider(widget.hostId).future,
      );
      await repository.ask(
        body: body,
        threadId: widget.threadId,
        delivery: repository.supportsDelivery
            ? effectiveInboxDelivery(_delivery, widget.recipient?.deliveryMode)
            : null,
      );
      _controller.clear();
    } on Object catch (error, stackTrace) {
      showActionFailure(
        messenger,
        action: 'send the follow-up',
        error: error,
        stackTrace: stackTrace,
        message: actionFailureMessage(
          'send the follow-up',
          inboxErrorMessage(error),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliverySupported =
        ref
            .watch(mobileInboxRepositoryProvider(widget.hostId))
            .value
            ?.supportsDelivery ??
        false;
    final enabled = _live && !_sending;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          if (!_live)
            const AleraNotice(
              icon: AleraIcons.info,
              message: "This agent's terminal is no longer running. Ask another agent with Ask Agent.",
            )
          else if (deliverySupported)
            InboxDeliveryChoice(
              key: const ValueKey<String>('inboxFollowUpDelivery'),
              selected: _delivery,
              targetMode: widget.recipient?.deliveryMode,
              enabled: enabled,
              compact: true,
              onChanged: (value) => setState(() => _delivery = value),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: _controller,
                  hintText: 'Ask a follow-up',
                  minLines: 1,
                  maxLines: 5,
                  enabled: _live,
                  keyboardType: TextInputType.multiline,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              IconButton(
                tooltip: 'Send Follow-Up',
                onPressed: enabled ? () => unawaited(_send()) : null,
                icon: const Icon(AleraIcons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
