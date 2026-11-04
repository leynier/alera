import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_usage_fallback.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The banner of chat [chatId] on [hostId], or null when its chat did not
/// fall back or the notice was dismissed. "Use Codex" moves the chat back to
/// the default agent with [select] (which throws when the runtime refuses),
/// through [run], which reports a failure; the banner closes once it worked.
Widget? agentChatUsageFallbackBannerOf(
  WidgetRef ref,
  String hostId,
  String chatId, {
  Future<void> Function(AgentChatSelection selection)? select,
  Future<void> Function(String what, Future<void> Function() action)? run,
}) {
  final fallback = ref.watch(
    agentChatUsageFallbacksProvider.select(
      (all) => all[agentChatUsageFallbackKey(hostId, chatId)],
    ),
  );
  if (fallback == null) return null;
  final notices = ref.read(agentChatUsageFallbacksProvider.notifier);
  final target = fallback.defaultSelection;
  return AgentChatUsageFallbackBanner(
    fallback: fallback,
    now: DateTime.now(),
    onDismiss: () => notices.dismiss(hostId, chatId),
    onUseDefault: target == null || select == null || run == null
        ? null
        : () => run('Could not change the agent.', () async {
            await select(target);
            notices.dismiss(hostId, chatId);
          }),
  );
}

/// "Using Claude · Codex is out of usage · resets at 14:30" above the
/// composer of a new chat that started on another agent because the default
/// one was out of usage. The tab shows it until it is dismissed or the first
/// message is sent.
class const AgentChatUsageFallbackBanner({
  super.key,
  required final AgentChatUsageFallback fallback,
  required final DateTime now,
  required final VoidCallback onDismiss,

  /// Switches the chat back to the default agent; null hides the action.
  final VoidCallback? onUseDefault,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final resets = _resetLabel(context);
    return AleraNotice(
      key: const ValueKey<String>('agent-chat-usage-fallback'),
      icon: AleraIcons.info,
      message: <String>[fallback.title, fallback.detail, ?resets].join(' · '),
      action: Row(
        mainAxisSize: .min,
        children: <Widget>[
          if (onUseDefault != null)
            TextButton(
              key: const ValueKey<String>(
                'agent-chat-usage-fallback-use-default',
              ),
              onPressed: onUseDefault,
              child: Text(fallback.useDefaultLabel),
            ),
          IconButton(
            key: const ValueKey<String>('agent-chat-usage-fallback-dismiss'),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(AleraIcons.close),
          ),
        ],
      ),
    );
  }

  /// "resets at 14:30" today, "resets Oct 14" later, or null when unknown.
  String? _resetLabel(BuildContext context) {
    final resetsAt = fallback.resetsAt?.toLocal();
    if (resetsAt == null) return null;
    final today = now.toLocal();
    final localizations = MaterialLocalizations.of(context);
    if (resetsAt.year == today.year &&
        resetsAt.month == today.month &&
        resetsAt.day == today.day) {
      final time = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(resetsAt),
        alwaysUse24HourFormat: true,
      );
      return 'resets at $time';
    }
    return 'resets ${localizations.formatShortMonthDay(resetsAt)}';
  }
}
