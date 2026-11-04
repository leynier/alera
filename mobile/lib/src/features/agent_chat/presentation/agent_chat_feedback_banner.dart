import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One `/feedback` submission above the composer, as T3 Code's phone shows
/// it: uploading, then the thread id to copy, or why it failed.
class const AgentChatFeedbackBanner({
  super.key,
  required final AgentChatFeedbackSubmission submission,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final notice = agentChatFeedbackNotice(submission);
    final feedbackId = submission.feedbackId;
    return Semantics(
      liveRegion: true,
      child: AleraNotice(
        key: ValueKey<String>('agent-chat-feedback-${submission.id}'),
        icon: submission.status == AgentChatFeedbackStatus.failed
            ? AleraIcons.warning
            : AleraIcons.info,
        message: switch (notice.detail) {
          final String detail => '${notice.title}\n$detail',
          null => notice.title,
        },
        action: submission.status == AgentChatFeedbackStatus.uploading
            ? null
            : Row(
                mainAxisSize: .min,
                children: <Widget>[
                  if (feedbackId != null)
                    TextButton(
                      key: const ValueKey<String>('agent-chat-feedback-copy'),
                      onPressed: () => unawaited(_copy(context, feedbackId)),
                      child: const Text('Copy ID'),
                    ),
                  IconButton(
                    key: const ValueKey<String>('agent-chat-feedback-dismiss'),
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                    icon: const Icon(AleraIcons.close),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String id) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: id));
    messenger?.showSnackBar(
      const SnackBar(content: Text('Copied the feedback thread ID.')),
    );
  }
}
