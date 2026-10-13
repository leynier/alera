import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

class const AgentChatLoadingView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const AleraEmptyState(
    key: ValueKey<String>('agent-chat-loading'),
    message: 'Opening chat',
    loading: true,
  );
}

class const AgentChatFailedView({
  super.key,
  required final String message,
  required final VoidCallback onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraEmptyState(
    title: 'Could Not Open Chat',
    message: message,
    icon: AleraIcons.warning,
    action: FilledButton(onPressed: onRetry, child: const Text('Try Again')),
  );
}

class const AgentChatUpdateRequiredView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraEmptyState(
    key: const ValueKey<String>('agent-chat-update-required'),
    title: 'Update Required',
    message: const AgentChatUpdateRequired().toString(),
    icon: AleraIcons.warning,
  );
}

class const AgentChatUnboundView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const AleraEmptyState(
    message: 'This tab is not linked to an agent chat.',
    icon: AleraIcons.agent,
  );
}

/// What a chat without messages shows: who will answer, and where.
class const AgentChatEmptyConversation({
  super.key,
  required final String title,
  required final String provider,
  required final String providerLabel,
  required final String? model,
  required final String workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey<String>('agent-chat-empty'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.emptyStateMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AgentChatProviderIcon(
                provider: provider,
                size: AleraTokens.iconEmptyState,
              ),
              const SizedBox(height: AleraTokens.space12),
              Text(
                title.trim().isEmpty ? 'New Chat' : title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AleraTokens.space6),
              Text(
                model == null ? providerLabel : '$providerLabel · $model',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                workspacePath,
                textAlign: TextAlign.center,
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              Text(
                'Send a message to start.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dismissible failure of the last action, above the composer.
class const AgentChatActionErrorBanner({
  super.key,
  required final String message,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraInlineNotice(
    key: const ValueKey<String>('agent-chat-action-error'),
    tone: AleraInlineNoticeTone.error,
    message: message,
    child: Align(
      alignment: Alignment.centerRight,
      child: TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
    ),
  );
}

class const AgentChatReconnectingBanner({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const AleraInlineNotice(
    key: ValueKey<String>('agent-chat-reconnecting'),
    tone: AleraInlineNoticeTone.warning,
    message:
        'Reconnecting to the Alera runtime. The chat keeps running there; '
        'this view catches up when the connection returns.',
  );
}

/// Why the session stopped and the ways back the runtime verified.
class const AgentChatRecoveryNotice({
  super.key,
  required final AgentChatRecovery recovery,
  required final bool recovering,
  required final VoidCallback onResume,
  required final VoidCallback onRestart,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tone = switch (recovery.kind) {
      AgentChatRecoveryKind.resumable => AleraInlineNoticeTone.info,
      _ => AleraInlineNoticeTone.warning,
    };
    final actions = <Widget>[
      if (recovery.canResume)
        FilledButton(
          onPressed: recovering ? null : onResume,
          child: const Text('Resume Session'),
        ),
      if (recovery.canRestart)
        TextButton(
          onPressed: recovering ? null : onRestart,
          child: const Text('Start New Session'),
        ),
    ];
    return AleraInlineNotice(
      key: const ValueKey<String>('agent-chat-recovery'),
      tone: tone,
      message: recovery.message,
      child: actions.isEmpty
          ? null
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: AleraTokens.space8,
              children: actions,
            ),
    );
  }
}

/// Messages the runtime holds until the running turn ends. Every client sees
/// the same queue and any of them can take an entry back.
class const AgentChatQueueDock({
  super.key,
  required final List<AgentChatQueueEntry> queue,
  required final Set<String> cancellingQueueIds,
  required final ValueChanged<String> onCancel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('agent-chat-queue'),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            queue.length == 1
                ? '1 message waits for this turn to end'
                : '${queue.length} messages wait for this turn to end',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          for (final entry in queue)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    entry.text.isEmpty
                        ? '${entry.attachments.length} attachments'
                        : entry.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                AleraIconButton(
                  key: ValueKey<String>(
                    'agent-chat-queue-cancel-${entry.queueId}',
                  ),
                  tooltip: 'Remove From Queue',
                  icon: AleraIcons.close,
                  iconSize: AleraTokens.iconSm,
                  minSize: AleraTokens.iconButtonSm,
                  onPressed: cancellingQueueIds.contains(entry.queueId)
                      ? null
                      : () => onCancel(entry.queueId),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
