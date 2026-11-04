import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';

/// A native rewind the host has not finished or could not confirm. It names
/// the operation, repeats the host's sentence, and offers exactly the
/// recovery actions the host allows; each asks first and none runs on its
/// own. While [busy] (a choice is on its way) every action is disabled, so a
/// choice is never sent twice. Nothing here navigates.
class const AgentChatNativeOperationBanner({
  super.key,
  required final AgentChatNativeOperation operation,
  required final bool enabled,
  required final bool busy,
  required final ValueChanged<AgentChatNativeHistoryAction> onAction,
}) extends StatelessWidget {
  Future<void> _choose(
    BuildContext context,
    AgentChatNativeHistoryAction action,
  ) async {
    final label = agentChatNativeOperationActionLabel(action);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: '$label?',
        message: agentChatNativeOperationActionDescription(action),
        confirmLabel: label,
        destructive: action == .restartFromTranscript,
      ),
    );
    if (confirmed ?? false) onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decide = operation.recovery?.needsReconciliation ?? false;
    final tone = decide ? AleraTokens.warning : AleraTokens.foregroundMuted;
    final actions = agentChatNativeOperationActions(operation);
    final ready = enabled && !busy;
    return ColoredBox(
      color: Color.alphaBlend(
        tone.withValues(alpha: AleraTokens.statusTintAlpha),
        AleraTokens.surfaceVariant,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space16,
          vertical: AleraTokens.space8,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: AleraTokens.space4,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (busy || !decide)
                  const SizedBox.square(
                    dimension: AleraTokens.space16,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                else
                  Icon(
                    AleraIcons.warning,
                    size: AleraTokens.space16,
                    color: tone,
                  ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    agentChatNativeOperationTitle(operation),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            Text(
              agentChatNativeOperationMessage(operation),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (actions.isNotEmpty)
              Wrap(
                alignment: .end,
                spacing: AleraTokens.space4,
                children: <Widget>[
                  for (final action in actions)
                    TextButton(
                      key: ValueKey<String>(
                        'agent-chat-native-action-${action.wire}',
                      ),
                      onPressed: ready
                          ? () => unawaited(_choose(context, action))
                          : null,
                      child: Text(agentChatNativeOperationActionLabel(action)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
