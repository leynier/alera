import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A delegated task that waits on a person, above the parent chat's Tasks
/// dock. Answer Here opens the child's requests in place; Open Chat is the
/// only way it leaves the chat. Presentational.
class const ChatTaskInputBanner({
  super.key,
  required final AgentChatTask task,
  required final bool answering,
  required final VoidCallback onAnswerHere,
  final VoidCallback? onOpenChat,
  final int otherCount = 0,
  final Widget? requests,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final more = otherCount > 0
        ? ' (and $otherCount more ${otherCount == 1 ? 'task' : 'tasks'})'
        : '';
    return Semantics(
      liveRegion: true,
      child: AleraInlineNotice(
        key: ValueKey<String>('chatTaskInputBanner:${task.id}'),
        message: 'Task needs input: ${task.displayTitle}$more',
        tone: .warning,
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: <Widget>[
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space4,
              children: <Widget>[
                Semantics(
                  expanded: answering,
                  child: FilledButton(
                    key: ValueKey<String>('chatTaskAnswerHere:${task.id}'),
                    onPressed: onAnswerHere,
                    child: Text(answering ? 'Hide Requests' : 'Answer Here'),
                  ),
                ),
                if (onOpenChat != null)
                  OutlinedButton(
                    key: ValueKey<String>('chatTaskBannerOpenChat:${task.id}'),
                    onPressed: onOpenChat,
                    child: const Text('Open Chat'),
                  ),
              ],
            ),
            if (answering && requests != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              requests!,
            ],
          ],
        ),
      ),
    );
  }
}
