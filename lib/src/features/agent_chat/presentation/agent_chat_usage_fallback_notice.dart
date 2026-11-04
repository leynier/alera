import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_usage_fallback.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Using Claude · Codex is out of usage · resets at 14:30" above the
/// composer of a new chat that started on another agent because the default
/// one was out of usage. The footer shows it until it is dismissed or the
/// first message is sent. "Use Codex" moves the chat back to the default
/// agent and model through [onUseDefault], then hides the notice.
class const AgentChatUsageFallbackNotice({
  super.key,
  required final String chatId,
  final Future<bool> Function(AgentChatSelection pick, {required String label})?
  onUseDefault,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = ref.watch(
      agentChatUsageFallbacksProvider.select((notices) => notices[chatId]),
    );
    if (fallback == null) return const SizedBox.shrink();
    final resets = agentChatResetLabel(
      context,
      fallback.resetsAt,
      now: ref.read(agentChatClockProvider)(),
    );
    return AleraInlineNotice(
      key: const ValueKey<String>('agent-chat-usage-fallback'),
      message: <String>[fallback.title, fallback.detail, ?resets].join(' · '),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: AleraTokens.space4,
          children: <Widget>[
            if ((onUseDefault, fallback.defaultSelection) case (
              final use?,
              final selection?,
            ))
              TextButton(
                key: const ValueKey<String>(
                  'agent-chat-usage-fallback-use-default',
                ),
                onPressed: () async {
                  final notices = ref.read(
                    agentChatUsageFallbacksProvider.notifier,
                  );
                  final label = fallback.defaultLabel ?? fallback.fromLabel;
                  if (await use(selection, label: label)) {
                    notices.dismiss(chatId);
                  }
                },
                child: Text(fallback.useDefaultLabel),
              ),
            TextButton(
              key: const ValueKey<String>('agent-chat-usage-fallback-dismiss'),
              onPressed: () => ref
                  .read(agentChatUsageFallbacksProvider.notifier)
                  .dismiss(chatId),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "resets at 14:30" today, "resets Oct 14" later, or null when unknown.
String? agentChatResetLabel(
  BuildContext context,
  DateTime? resetsAt, {
  required DateTime now,
}) {
  if (resetsAt == null) return null;
  final local = resetsAt.toLocal();
  final today = now.toLocal();
  final localizations = MaterialLocalizations.of(context);
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );
    return 'resets at $time';
  }
  return 'resets ${localizations.formatShortMonthDay(local)}';
}
