import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_feedback.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs `/feedback` from the composer when [available] and the message is
/// the command alone. Returns whether it took the send; the composer then
/// keeps its draft, which clears only once the person confirms the upload.
bool handleAgentChatFeedbackSend(
  BuildContext context,
  WidgetRef ref, {
  required AgentChatRef chat,
  required bool available,
  required bool neverSent,
  required TerminalComposerController composer,
  required String text,
  required List<AgentChatAttachment> attachments,
}) {
  if (!available || attachments.isNotEmpty) return false;
  final command = parseAgentChatFeedbackCommand(text);
  if (command == null) return false;
  if (neverSent) {
    AleraToast.publish(
      message: agentChatFeedbackNeedsConversationMessage,
      tone: AleraToastTone.warning,
    );
    return true;
  }
  final submissions = ref.read(agentChatFeedbackSubmissionsProvider.notifier);
  if (!submissions.claim(chat.chatId)) return true;
  unawaited(
    _confirmAndSubmit(
      context,
      submissions,
      chat: chat,
      command: command,
      composer: composer,
      text: text.trim(),
    ),
  );
  return true;
}

Future<void> _confirmAndSubmit(
  BuildContext context,
  AgentChatFeedbackSubmissions submissions, {
  required AgentChatRef chat,
  required AgentChatFeedbackCommand command,
  required TerminalComposerController composer,
  required String text,
}) async {
  final draft = composer.textController.text;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: agentChatFeedbackConsentTitle,
      message: agentChatFeedbackConsentMessage(command),
      confirmLabel: agentChatFeedbackConsentConfirmLabel,
    ),
  );
  if (confirmed != true) {
    submissions.release(chat.chatId);
    return;
  }
  if (composer.textController.text == draft) composer.textController.clear();
  await submissions.submit(chat, command, text: text);
}

/// The chat's `/feedback` submissions above its composer, as T3 Code's
/// composer banners show them: uploading, then the thread id to copy, or
/// why it failed.
class const AgentChatFeedbackBanner({
  super.key,
  required final AgentChatFeedbackSubmission submission,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final notice = agentChatFeedbackNotice(submission);
    final uploading = submission.status == AgentChatFeedbackStatus.uploading;
    return Semantics(
      liveRegion: true,
      child: AleraInlineNotice(
        key: ValueKey<String>('agent-chat-feedback-${submission.id}'),
        message: switch (notice.detail) {
          final String detail => '${notice.title}\n$detail',
          null => notice.title,
        },
        tone: submission.status == AgentChatFeedbackStatus.failed
            ? AleraInlineNoticeTone.error
            : AleraInlineNoticeTone.info,
        child: uploading
            ? null
            : Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: AleraTokens.space8,
                children: <Widget>[
                  if (submission.feedbackId case final String id)
                    TextButton(
                      key: const ValueKey<String>('agent-chat-feedback-copy'),
                      onPressed: () => unawaited(_copy(id)),
                      child: const Text('Copy ID'),
                    ),
                  TextButton(
                    key: const ValueKey<String>('agent-chat-feedback-dismiss'),
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _copy(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    AleraToast.publish(
      message: 'Copied the feedback thread ID.',
      tone: AleraToastTone.success,
    );
  }
}
