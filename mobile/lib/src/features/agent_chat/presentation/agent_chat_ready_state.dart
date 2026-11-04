import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A chat nothing was sent to yet: which agent and model will answer, where
/// it works, and that the first message starts it. A never-sent chat is
/// ready, not stopped, even after the host restarted.
class const AgentChatReadyState({
  super.key,
  required final String? agentType,
  required final String agentLabel,
  required final String? modelLabel,
  required final String? workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.emptyStateMaxWidth,
        ),
        child: Padding(
          padding: AleraTokens.pagePadding,
          child: Column(
            mainAxisSize: .min,
            spacing: AleraTokens.space8,
            children: <Widget>[
              if (agentType case final type?)
                AgentIdentityIcon(
                  agentType: type,
                  size: AleraTokens.space32,
                  showTooltip: false,
                )
              else
                const Icon(AleraIcons.agent, size: AleraTokens.space32),
              Text(agentLabel, style: theme.textTheme.titleMedium),
              if (modelLabel case final model?) Text(model, style: muted),
              if (workspacePath case final path? when path.isNotEmpty)
                Text(
                  path,
                  style: AleraTokens.monoStyle,
                  textAlign: .center,
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
              Text(agentChatReadyMessage, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chat went away on another device while this phone still held unsent
/// text for it. The text is offered back; nothing navigates.
class const AgentChatRemovedState({
  super.key,
  required final String draftText,
  required final VoidCallback? onStartNewChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraEmptyState(
    icon: AleraIcons.archive,
    title: 'Chat removed',
    message: draftText.isEmpty
        ? 'This chat was closed on another device before anything was sent.'
        : 'This chat was closed on another device. Your unsent text is kept '
              'here.',
    action: draftText.isEmpty
        ? null
        : Wrap(
            alignment: .center,
            spacing: AleraTokens.space8,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => unawaited(_copy(context)),
                icon: const Icon(AleraIcons.copy),
                label: const Text('Copy'),
              ),
              if (onStartNewChat != null)
                FilledButton(
                  onPressed: onStartNewChat,
                  child: const Text('Start New Chat With This Text'),
                ),
            ],
          ),
  );

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: draftText));
    messenger?.showSnackBar(const SnackBar(content: Text('Text copied')));
  }
}
