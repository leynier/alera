import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_usage_fallback.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The banner of chat [chatId] on [hostId], or null when its chat did not
/// fall back or the notice was dismissed.
Widget? agentChatUsageFallbackBannerOf(
  WidgetRef ref,
  String hostId,
  String chatId,
) {
  final fallback = ref.watch(
    agentChatUsageFallbacksProvider.select(
      (all) => all[agentChatUsageFallbackKey(hostId, chatId)],
    ),
  );
  if (fallback == null) return null;
  return AgentChatUsageFallbackBanner(
    fallback: fallback,
    now: DateTime.now(),
    onDismiss: () => ref
        .read(agentChatUsageFallbacksProvider.notifier)
        .dismiss(hostId, chatId),
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
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final resets = _resetLabel(context);
    return AleraNotice(
      key: const ValueKey<String>('agent-chat-usage-fallback'),
      icon: AleraIcons.info,
      message: <String>[fallback.title, fallback.detail, ?resets].join(' · '),
      action: IconButton(
        key: const ValueKey<String>('agent-chat-usage-fallback-dismiss'),
        tooltip: 'Dismiss',
        onPressed: onDismiss,
        icon: const Icon(AleraIcons.close),
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
